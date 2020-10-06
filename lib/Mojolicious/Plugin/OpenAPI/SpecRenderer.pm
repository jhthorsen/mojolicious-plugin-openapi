package Mojolicious::Plugin::OpenAPI::SpecRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use JSON::Validator;
use Mojo::JSON;
use Mojo::Util 'deprecated';

use constant DEBUG    => $ENV{MOJO_OPENAPI_DEBUG} || 0;
use constant MARKDOWN => eval 'require Text::Markdown;1';

sub register {
  my ($self, $app, $config) = @_;

  $app->defaults(openapi_spec_renderer_logo        => '/mojolicious/plugin/openapi/logo.png');
  $app->defaults(openapi_spec_renderer_theme_color => '#508a25');

  $self->{standalone} = $config->{openapi} ? 0 : 1;
  $app->helper('openapi.render_spec' => sub { $self->_render_spec(@_) });

  # EXPERIMENTAL
  $app->helper('openapi.spec_iterator' => \&_helper_iterator);

  unless ($app->{'openapi.render_specification'}++) {
    push @{$app->renderer->classes}, __PACKAGE__;
    push @{$app->static->classes},   __PACKAGE__;
  }

  $self->_register_with_openapi($app, $config) unless $self->{standalone};
}

sub _helper_iterator {
  my ($c, $obj) = @_;
  return unless $obj;

  unless ($c->{_helper_iterator}{$obj}) {
    my $x_re = qr{^x-};
    $c->{_helper_iterator}{$obj}
      = [map { [$_, $obj->{$_}] } sort { lc $a cmp lc $b } grep { !/$x_re/ } keys %$obj];
  }

  my $items = $c->{_helper_iterator}{$obj};
  my $item  = shift @$items;
  delete $c->{_helper_iterator}{$obj} unless $item;
  return $item ? @$item : ();
}

sub _register_with_openapi {
  my ($self, $app, $config) = @_;
  my $openapi = $config->{openapi};

  if ($config->{render_specification} // 1) {
    my $spec_route = $openapi->route->get('/')->to(cb => sub { shift->openapi->render_spec(@_) });
    my $name       = $config->{spec_route_name} || $openapi->validator->get('/x-mojo-name');
    $spec_route->name($name) if $name;
  }

  if ($config->{render_specification_for_paths} // 1) {
    $app->plugins->once(openapi_routes_added => sub { $self->_add_documentation_routes(@_) });
  }
}

sub _add_documentation_routes {
  my ($self, $openapi, $routes) = @_;
  my %dups;

  for my $route (@$routes) {
    my $route_path = $route->to_string;
    next if $dups{$route_path}++;

    my $openapi_path = $route->to->{'openapi.path'};
    my $doc_route
      = $openapi->route->options($route->pattern->unparsed, {'openapi.default_options' => 1});
    $doc_route->to(cb => sub { $self->_render_spec(shift, $openapi_path) });
    $doc_route->name(join '_', $route->name, 'openapi_documentation')              if $route->name;
    warn "[OpenAPI] Add route options $route_path (@{[$doc_route->name // '']})\n" if DEBUG;
  }
}

sub _markdown {
  return Mojo::ByteStream->new(MARKDOWN ? Text::Markdown::markdown($_[0]) : $_[0]);
}

sub _render_partial_spec {
  my ($self, $c, $path, $custom_spec) = @_;

  my $validator
    = $custom_spec        ? JSON::Validator->new->schema($custom_spec)
    : $self->{standalone} ? JSON::Validator->new->schema($c->stash('openapi_spec'))
    :                       Mojolicious::Plugin::OpenAPI::_self($c)->validator;

  my $method  = $c->param('method');
  my $bundled = $validator->get([paths => $path]);
  $bundled = $validator->bundle({schema => $bundled}) if $bundled;
  my $definitions = $bundled->{definitions} || {} if $bundled;
  my $parameters  = $bundled->{parameters}  || [];

  if ($method and $bundled = $bundled->{$method}) {
    push @$parameters, @{$bundled->{parameters} || []};
  }

  return $c->render(json => {errors => [{message => 'No spec defined.'}]}, status => 404)
    unless $bundled;

  delete $bundled->{$_} for qw(definitions parameters);
  return $c->render(
    json => {
      '$schema'   => 'http://json-schema.org/draft-04/schema#',
      title       => $validator->get([qw(info title)]) || '',
      description => $validator->get([qw(info description)]) || '',
      definitions => $definitions,
      parameters  => $parameters,
      %$bundled,
    }
  );
}

sub _render_spec {
  my ($self, $c, $path, $custom_spec) = @_;
  deprecated '"openapi_spec" in stash is DEPRECATED'          if $c->stash('openapi_spec');
  return $self->_render_partial_spec($c, $path, $custom_spec) if $path;

  my $openapi
    = $custom_spec || $self->{standalone} ? undef : Mojolicious::Plugin::OpenAPI::_self($c);
  my $format = $c->stash('format') || 'json';
  my %spec;

  if ($custom_spec) {
    %spec = %$custom_spec;
  }
  elsif ($openapi) {
    my $req_url = $c->req->url->to_abs;
    $openapi->{bundled} ||= $openapi->validator->bundle;
    %spec = %{$openapi->{bundled}};

    if ($openapi->validator->version ge '3') {
      $spec{servers}[0]{url} = $req_url->to_string;
      $spec{servers}[0]{url} =~ s!\.(html|json)$!!;
      delete $spec{basePath};    # Added by Plugin::OpenAPI
    }
    else {
      $spec{basePath}   = $c->url_for($spec{basePath});
      $spec{host}       = $req_url->host_port;
      $spec{schemes}[0] = $req_url->scheme;
    }
  }
  elsif ($c->stash('openapi_spec')) {
    %spec = %{$c->stash('openapi_spec') || {}};
  }

  return $c->render(json => {errors => [{message => 'No specification to render.'}]}, status => 500)
    unless %spec;

  my ($x_re, $base_url, @operations) = (qr{^x-});
  if ($format eq 'html') {
    for my $path (keys %{$spec{paths}}) {
      next if $path =~ $x_re;
      my $path_spec = $openapi ? $openapi->validator->get([paths => $path]) : $spec{paths}{$path};
      for my $method (keys %$path_spec) {
        next if $method =~ $x_re;
        my $op_spec = $path_spec->{$method};
        next unless ref $op_spec eq 'HASH';
        push @operations,
          {
          method  => $method,
          name    => $op_spec->{operationId} ? $op_spec->{operationId} : join(' ', $method, $path),
          path    => $path,
          op_spec => $op_spec,
          };
      }
    }

    $base_url
      = exists $spec{openapi}
      ? Mojo::URL->new($spec{servers}[0]{url})
      : Mojo::URL->new->host($spec{host} || 'localhost')->path($spec{basePath})
      ->scheme($spec{schemes}[0]);
  }

  return $c->render(json => \%spec) unless $format eq 'html';
  return $c->render(
    base_url   => $base_url,
    handler    => 'ep',
    template   => 'mojolicious/plugin/openapi/layout',
    markdown   => \&_markdown,
    operations => [sort { $a->{name} cmp $b->{name} } @operations],
    serialize  => \&_serialize,
    slugify    => sub {
      join '-', map { s/\W/-/g; lc } map {"$_"} @_;
    },
    spec => \%spec,
  );
}

sub _serialize { Mojo::JSON::encode_json(@_) }

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI::SpecRenderer - Render OpenAPI specification

=head1 SYNOPSIS

=head2 With Mojolicious::Plugin::OpenAPI

  $app->plugin(OpenAPI => {
    plugins                        => [qw(+SpecRenderer)],
    render_specification           => 1,
    render_specification_for_paths => 1,
    %openapi_parameters,
  });

See L<Mojolicious::Plugin::OpenAPI/register> for what
C<%openapi_parameters> might contain.

=head2 Standalone

  use Mojolicious::Lite;
  plugin "Mojolicious::Plugin::OpenAPI::SpecRenderer";

  # Some specification to render
  my $petstore = app->home->child("petstore.json");

  get "/my-spec" => sub {
    my $c    = shift;
    my $path = $c->param('path') || '/';
    state $custom_spec = JSON::Validator->new->schema($petstore->to_string)->bundle;
    $c->openapi->render_spec($path, $custom_spec);
  };

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI::SpecRenderer> will enable
L<Mojolicious::Plugin::OpenAPI> to render the specification in both HTML and
JSON format. It can also be used L</Standalone> if you just want to render
the specification, and not add any API routes to your application.

See L</TEMPLATING> to see how you can override parts of the rendering.

The human readable format focus on making the documentation printable, so you
can easily share it with third parties as a PDF. If this documentation format
is too basic or has missing information, then please
L<report in|https://github.com/jhthorsen/mojolicious-plugin-openapi/issues>
suggestions for enhancements.

See L<https://demo.convos.by/api.html> for a demo.

=head1 HELPERS

=head2 openapi.render_spec

  $c = $c->openapi->render_spec;
  $c = $c->openapi->render_spec($json_path);
  $c = $c->openapi->render_spec($json_path, \%custom_spec);
  $c = $c->openapi->render_spec("/user/{id}");

Used to render the specification as either "html" or "json". Set the
L<Mojolicious/stash> variable "format" to change the format to render.

Will render the whole specification by default, but can also render
documentation for a given OpenAPI path.

=head1 METHODS

=head2 register

  $doc->register($app, $openapi, \%config);

Adds the features mentioned in the L</DESCRIPTION>.

C<%config> is the same as passed on to
L<Mojolicious::Plugin::OpenAPI/register>. The following keys are used by this
plugin:

=head3 render_specification

Render the whole specification as either HTML or JSON from "/:basePath".
Example if C<basePath> in your specification is "/api":

  GET https://api.example.com/api.html
  GET https://api.example.com/api.json

Disable this feature by setting C<render_specification> to C<0>.

=head3 render_specification_for_paths

Render the specification from individual routes, using the OPTIONS HTTP method.
Example:

  OPTIONS https://api.example.com/api/some/path.json
  OPTIONS https://api.example.com/api/some/path.json?method=post

Disable this feature by setting C<render_specification_for_paths> to C<0>.

=head1 TEMPLATING

Overriding templates is EXPERIMENTAL, but not very likely to break in a bad
way.

L<Mojolicious::Plugin::OpenAPI::SpecRenderer> uses many template files to make
up the human readable version of the spec. Each of them can be overridden by
creating a file in your templates folder.

  mojolicious/plugin/openapi/layout.html.ep
  |- mojolicious/plugin/openapi/head.html.ep
  |  '- mojolicious/plugin/openapi/style.html.ep
  |- mojolicious/plugin/openapi/header.html.ep
  |  |- mojolicious/plugin/openapi/logo.html.ep
  |  '- mojolicious/plugin/openapi/toc.html.ep
  |- mojolicious/plugin/openapi/intro.html.ep
  |- mojolicious/plugin/openapi/resources.html.ep
  |  '- mojolicious/plugin/openapi/resource.html.ep
  |     |- mojolicious/plugin/openapi/human.html.ep
  |     |- mojolicious/plugin/openapi/parameters.html.ep
  |     '- mojolicious/plugin/openapi/response.html.ep
  |        '- mojolicious/plugin/openapi/human.html.ep
  |- mojolicious/plugin/openapi/references.html.ep
  |- mojolicious/plugin/openapi/footer.html.ep
  |- mojolicious/plugin/openapi/javascript.html.ep
  '- mojolicious/plugin/openapi/foot.html.ep

See the DATA section in the source code for more details on styling and markup
structure.

L<https://github.com/jhthorsen/mojolicious-plugin-openapi/blob/master/lib/Mojolicious/Plugin/OpenAPI/SpecRenderer.pm>

Variables available in the templates:

  %= $markdown->("# markdown\nstring\n")
  %= $serialize->($data_structure)
  %= $slugify->(@str)
  %= $spec->{info}{title}

In addition, there is a logo in "header.html.ep" that can be overriden by
either changing the static file "mojolicious/plugin/openapi/logo.png" or set
"openapi_spec_renderer_logo" in L<stash|Mojolicious::Controller/stash> to a
custom URL.

=head1 SEE ALSO

L<Mojolicious::Plugin::OpenAPI>

=cut

__DATA__
@@ mojolicious/plugin/openapi/header.html.ep
<header class="openapi-header">
  <h1 id="title"><%= $spec->{info}{title} || 'No title' %></h1>
  <p class="version"><span>Version</span> <span class="version"><%= $spec->{info}{version} %> - OpenAPI <%= $spec->{swagger} || $spec->{openapi} %></span></p>
</header>

<nav class="openapi-nav">
  <a href="#top" class="openapi-logo">
    %= image stash('openapi_spec_renderer_logo'), alt => 'OpenAPI Logo'
  </a>
  %= include 'mojolicious/plugin/openapi/toc'
</nav>
@@ mojolicious/plugin/openapi/intro.html.ep
<h2 id="about">About</h2>
% if ($spec->{info}{description}) {
<div class="description">
  %== $markdown->($spec->{info}{description})
</div>
% }

% my $contact = $spec->{info}{contact};
% my $license = $spec->{info}{license};
<h3 id="license"><a href="#top">License</a></h3>
% if ($license->{name}) {
<p class="license"><a href="<%= $license->{url} || '' %>"><%= $license->{name} %></a></p>
% } else {
<p class="no-license">No license specified.</p>
% }

<h3 id="contact"<a href="#top">Contact information</a></h3>
% if ($contact->{email}) {
<p class="contact-email"><a href="mailto:<%= $contact->{email} %>"><%= $contact->{email} %></a></p>
% }
% if ($contact->{url}) {
<p class="contact-url"><a href="<%= $contact->{url} %>"><%= $contact->{url} %></a></p>
% }

% if (exists $spec->{openapi}) {
  <h3 id="servers"><a href="#top">Servers</a></h3>
  <ul class="unstyled">
  % for my $server (@{$spec->{servers}}){
    <li><a href="<%= $server->{url} %>"><%= $server->{url} %></a><%= $server->{description} ? ' - '.$server->{description} : '' %></li>
  % }
  </ul>
% } else {
  % my $schemes = $spec->{schemes} || ["http"];
  % my $url = Mojo::URL->new("http://$spec->{host}");
  <h3 id="baseurl"><a href="#top">Base URL</a></h3>
  <ul class="unstyled">
  % for my $scheme (@$schemes) {
    % $url->scheme($scheme);
    <li><a href="<%= $url %>"><%= $url %></a></li>
  % }
  </ul>
% }

% if ($spec->{info}{termsOfService}) {
<h3 id="terms-of-service"><a href="#top">Terms of service</a></h3>
<p class="terms-of-service">
  %= $spec->{info}{termsOfService}
</p>
% }
@@ mojolicious/plugin/openapi/foot.html.ep
<a href="#top" class="openapi-up-button" type="button">&#8963;</a>
<script>
new SpecRenderer().setup();
</script>
@@ mojolicious/plugin/openapi/footer.html.ep
<!-- default footer -->
@@ mojolicious/plugin/openapi/head.html.ep
<title><%= $spec->{info}{title} || 'No title' %></title>
<meta charset="utf-8">
<meta http-equiv="X-UA-Compatible" content="chrome=1">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=2.0">
%= include 'mojolicious/plugin/openapi/style'
@@ mojolicious/plugin/openapi/human.html.ep
% if ($op_spec->{summary}) {
<p class="spec-summary"><%= $op_spec->{summary} %></p>
% }
% if ($op_spec->{description}) {
<div class="spec-description"><%== $markdown->($op_spec->{description}) %></div>
% }
% if (!$op_spec->{description} and !$op_spec->{summary}) {
<p class="op-summary op-doc-missing">This resource is not documented.</p>
% }
@@ mojolicious/plugin/openapi/parameters.html.ep
% my $has_parameters = @{$op_spec->{parameters} || []};
% my $body;
<h4 class="op-parameters">Parameters</h3>
% if ($has_parameters) {
<table class="op-parameters">
  <thead>
    <tr>
      <th>Name</th>
      <th>In</th>
      <th>Type</th>
      <th>Required</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
% }
% for my $p (@{$op_spec->{parameters} || []}) {
  % $body = $p->{schema} if $p->{in} eq 'body';
  <tr>
    % if ($spec->{parameters}{$p->{name}}) {
      <td><a href="#<%= $slugify->(qw(ref parameters), $p->{name}) %>"><%= $p->{name} %></a></td>
    % } else {
      <td><%= $p->{name} %></td>
    % }
    <td><%= $p->{in} %></td>
    <td><%= $p->{type} || $p->{schema}{type} %></td>
    <td><%= $p->{required} ? "Yes" : "No" %></td>
    <td><%== $p->{description} ? $markdown->($p->{description}) : "" %></td>
  </tr>
% }
% if ($has_parameters) {
  </tbody>
</table>
% } else {
<p class="op-parameters">This resource has no input parameters.</p>
% }
% if ($body) {
<h4 class="op-parameter-body">Body</h4>
<pre class="op-parameter-body"><%= $serialize->($body) %></pre>
% }
% if ($op_spec->{requestBody}) {
<h4 class="op-parameter-body">requestBody</h4>
<pre class="op-parameter-body"><%= $serialize->($op_spec->{requestBody}{content}) %></pre>
% }
@@ mojolicious/plugin/openapi/response.html.ep
% while (my ($code, $res) = $c->openapi->spec_iterator($op_spec->{responses})) {
  <h4 class="op-response">Response <%= $code %></h3>
  %= include 'mojolicious/plugin/openapi/human', op_spec => $res
  <pre class="op-response"><%= $serialize->($res->{schema} || $res->{content}) %></pre>
% }
@@ mojolicious/plugin/openapi/resource.html.ep
<h3 id="<%= $slugify->(op => $method, $path) %>" class="op-path <%= $op_spec->{deprecated} ? "deprecated" : "" %>"><a href="#top"><%= $name %></a></h3>
% if ($op_spec->{deprecated}) {
<p class="op-deprecated">This resource is deprecated!</p>
% }
<ul class="unstyled">
  <li><b><%= uc $method %></b> <a href="<%= "$base_url$path" %>"><%= $base_url->path . $path %></a></li>
  % if ($op_spec->{operationId}) {
  <li><b>Operation ID:</b> <span><%= $op_spec->{operationId} %></span></li>
  % }
</ul>
%= include 'mojolicious/plugin/openapi/human', op_spec => $op_spec
%= include 'mojolicious/plugin/openapi/parameters', op_spec => $op_spec
%= include 'mojolicious/plugin/openapi/response', op_spec => $op_spec
@@ mojolicious/plugin/openapi/references.html.ep
% if ($spec->{parameters}) {
  <h2 id="parameters"><a href="#top">Parameters</a></h2>
  % while (my ($key, $schema) = $c->openapi->spec_iterator($spec->{parameters})) {
    <h3 id="<%= lc $slugify->(qw(ref parameters), $key) %>"><a href="#top"><%= $key %></a></h3>
    <pre class="ref"><%= $serialize->($schema) %></pre>
  % }
  </li>
% }

% if ($spec->{components}) {
  <h2 id="components"><a href="#top">Components</a></h2>
  % while (my ($type, $comp_group) = $c->openapi->spec_iterator($spec->{components})) {
    % while (my ($key, $comp) = $c->openapi->spec_iterator($comp_group)) {
      <li><a href="#<%= lc $slugify->(qw(ref components), $key) %>"><%= $key %></a></li>
    % }
  % }
% }

% if ($spec->{definitions}) {
  <h2 id="definitions"><a href="#top">Parameters</a></h2>
  % while (my ($key, $schema) = $c->openapi->spec_iterator($spec->{definitions})) {
    <h3 id="<%= lc $slugify->(qw(ref definitions), $key) %>"><a href="#top"><%= $key %></a></h3>
    <pre class="ref"><%= $serialize->($schema) %></pre>
  % }
  </li>
% }
@@ mojolicious/plugin/openapi/resources.html.ep
<h2 id="resources"><a href="#top">Resources</a></h2>
% for my $op (@$operations) {
  %= include 'mojolicious/plugin/openapi/resource', %$op;
% }
@@ mojolicious/plugin/openapi/toc.html.ep
<ol id="toc">
  % if ($spec->{info}{description}) {
  <li class="for-description">
    <a href="#about">About</a>
    <ol>
      <li><a href="#license">License</a></li>
      <li><a href="#contact">Contact</a></li>
      <li><a href="#baseurl">Base URL</a></li>
      % if ($spec->{info}{termsOfService}) {
        <li class="for-terms"><a href="#terms-of-service">Terms of service</a></li>
      % }
    </ol>
  </li>
  % }
  <li class="for-resources">
    <a href="#resources">Resources</a>
    <ol>
      % for my $op (@$operations) {
        <li><a href="#<%= $slugify->(op => @$op{qw(method path)}) %>"><%= $op->{name} %></a></li>
      % }
    </ol>
  </li>

  % if ($spec->{parameters}) {
    <li class="for-references for-parameters">
      <a href="#references">Parameters</a>
      <ol>
        % while (my ($key) = $c->openapi->spec_iterator($spec->{parameters})) {
          <li><a href="#<%= lc $slugify->(qw(ref parameters), $key) %>"><%= $key %></a></li>
        % }
      </ol>
    </li>
  % }

  % if ($spec->{components}) {
    <li class="for-references for-components">
      <a href="#references">Components</a>
      <ol>
        % while (my ($type, $comp_group) = $c->openapi->spec_iterator($spec->{components})) {
          % while (my ($key, $comp) = $c->openapi->spec_iterator($comp_group)) {
            <li><a href="#<%= lc $slugify->(qw(ref components), $key) %>"><%= $key %></a></li>
          % }
        % }
      </ol>
    </li>
  % }

  % if ($spec->{definitions}) {
    <li class="for-references for-definitions">
      <a href="#references">Definitions</a>
      <ol>
        % while (my ($key) = $c->openapi->spec_iterator($spec->{definitions})) {
          <li><a href="#<%= lc $slugify->(qw(ref definitions), $key) %>"><%= $key %></a></li>
        % }
      </ol>
    </li>
  % }
</ol>
@@ mojolicious/plugin/openapi/layout.html.ep
<!doctype html>
<html lang="en">
<head>
  %= include 'mojolicious/plugin/openapi/head'
</head>
<body>
<div id="top" class="container openapi-container">
  %= include 'mojolicious/plugin/openapi/header'

  <article class="openapi-spec">
    <section class="openapi-spec_intro">
      %= include 'mojolicious/plugin/openapi/intro'
    </section>
    <section class="openapi-spec_resources">
      %= include 'mojolicious/plugin/openapi/resources'
    </section>
    <section class="openapi-spec_references">
      %= include 'mojolicious/plugin/openapi/references'
    </section>
  </article>

  <footer class="openapi-footer">
    %= include 'mojolicious/plugin/openapi/footer'
  </footer>
</div>

%= include "mojolicious/plugin/openapi/javascript"
%= include "mojolicious/plugin/openapi/foot"
</body>
</html>
@@ mojolicious/plugin/openapi/javascript.html.ep
<script>
var SpecRenderer = function() {};

function findVisibleElements(containerEl) {
  var els = [].slice.call(containerEl.childNodes, 0);
  var haystack = [];

  // Filter out comments, text nodes, ...
  var i = 0;
  while (i < els.length) {
    if (els[i].nodeType == Node.ELEMENT_NODE) {
      haystack.push([i, els[i]]);
      i++;
    }
    else {
      els.splice(i, 1);
    }
  }

  // No child nodes
  if (!els.length) return [];

  // Find fist visible element
  var scrollTop = document.documentElement.scrollTop || document.body.scrollTop;
  while (haystack.length > 1) {
    var i = Math.floor(haystack.length / 2);
    if (haystack[i][1].offsetTop <= scrollTop) {
      haystack.splice(0, i);
    }
    else {
      haystack.splice(i);
    }
  }

  if (!haystack.length) haystack.push([0, els[0]]);

  // Figure out the first and last visible element
  var offsetHeight = window.innerHeight;
  var firstIdx = haystack[0][0];
  var lastIdx = firstIdx;
  while (lastIdx < els.length) {
    if (els[lastIdx].offsetTop > scrollTop + offsetHeight) break;
    lastIdx++;
  }

  return els.slice(firstIdx, lastIdx);
}

SpecRenderer.prototype.jsonhtmlify
  = function(e){let n=document.createElement('div');const t=[[e,n]],s=[];for(;t.length;){const[e,l]=t.shift();let a,c,o=typeof e;if(null===e||'undefined'==o?o='null':Array.isArray(e)&&(o='array'),'array'==o)(c=(e=>e)).len=e.length,(a=document.createElement('div')).className='json-array '+(c.len?'has-items':'is-empty');else if('object'==o){const n=Object.keys(e).sort();(c=(e=>n[e])).len=n.length,(a=document.createElement('div')).className='json-object '+(c.len?'has-items':'is-empty')}else(a=document.createElement('span')).className='json-'+o,a.textContent='null'==o?'null':'boolean'!=o?e:e?'true':'false';if(c){const i=document.createElement('span');if(i.className='json-type',i.textContent=c.len?o+'['+c.len+']':'{}',l.appendChild(i),-1!=s.indexOf(e))n.classList.add('has-recursive-items'),a.classList.add('is-seen');else{for(let n=0;n<c.len;n++){const s=c(n),l=document.createElement('div'),o=document.createElement('span');o.className='json-key',o.textContent=s,l.appendChild(o),a.appendChild(l),t.push([e[s],l])}s.push(e)}}l.className='json-item '+a.className.replace(/^json-/,'contains-'),l.appendChild(a)}return n}

SpecRenderer.prototype.renderNav = function() {
  var i = 0;
  if (this.firstHeadingEl.offsetTop < this.scrollTop) {
    for (i = 0; i < this.headings.length; i++) {
      if (this.headings[i].offsetTop >= this.scrollTop + this.wh - this.headingOffsetTop) break;
    }
  }

  if (i > 0) i--;

  var id = this.headings[i] && this.headings[i].id || '';
  var aEl = document.querySelector('.openapi-nav a[href$="#' + id + '"]');
  for (i = 0; i < this.aEls.length; i++) {
    this.aEls[i].parentNode.classList[this.aEls[i] == aEl ? 'add' : 'remove']('is-active');
  }
};

SpecRenderer.prototype.renderPreTags = function() {
  var ki, pi;
  for (pi = 0; pi < this.visiblePreTags.length; pi++) {
    var preEl = this.visiblePreTags[pi];
    var jsonEl = this.jsonhtmlify(JSON.parse(preEl.innerText));
    jsonEl.classList.add('json-container');
    preEl.parentNode.replaceChild(jsonEl, preEl);

    var keyEls = jsonEl.querySelectorAll('.json-key');
    for (ki = 0; ki < keyEls.length; ki++) {
      if (keyEls[ki].textContent != '$ref') continue;
      var refEl = keyEls[ki].nextElementSibling;
      refEl.parentNode.replaceChild(this.renderRefLink(refEl), refEl);
    }
  }
};

SpecRenderer.prototype.renderRefLink = function(refEl) {
  var a = document.createElement('a');
  var href = refEl.textContent.replace(/'/g, '');
  a.textContent = refEl.textContent;
  a.href = href.match(/^#/) ? '#ref-' + href.replace(/\W/g, '-').substring(2).toLowerCase() : href;
  return a;
};

SpecRenderer.prototype.renderUpButton = function() {
  this.upButton.classList[this.scrollTop > 150 ? 'add' : 'remove']('is-visible');
};

SpecRenderer.prototype.render = function() {
  this.scrollTop = document.documentElement.scrollTop || document.body.scrollTop;

  var visiblePreTags = [];
  findVisibleElements(document.querySelector('.openapi-spec')).forEach(function(el) {
    findVisibleElements(el).forEach(function(el) {
      if (el.tagName.toLowerCase() == 'pre') visiblePreTags.push(el);
    });
  });

  this.visiblePreTags = visiblePreTags;
  this.renderNav();
  this.renderPreTags();
  this.renderUpButton();
};

SpecRenderer.prototype.scrollSpy = function(e) {
  // Do not run this method too often
  if (e && e.preventDefault) return this._scrollSpyTid || (this._scrollSpyTid = setTimeout(this.scrollSpy, 100));
  if (this._scrollSpyTid) clearTimeout(this._scrollSpyTid);
  delete this._scrollSpyTid;

  this.wh = window.innerHeight;
  this.headingOffsetTop = parseInt(this.wh / 2.3, 10);
  this.render();
}

SpecRenderer.prototype.setup = function() {
  this.aEls = document.querySelectorAll('.openapi-nav a');
  this.firstHeadingEl = document.querySelector('h2');
  this.headings = document.querySelectorAll('h3[id]');
  this.upButton = document.querySelector('.openapi-up-button');
  this.scrollSpy = this.scrollSpy.bind(this);
  this.render();

  var self = this;
  ['click', 'resize', 'scroll'].forEach(function(name) { window.addEventListener(name, self.scrollSpy) });
};
</script>
@@ mojolicious/plugin/openapi/style.html.ep
<style>
  * { box-sizing: border-box; }
  html, body {
    background: #f7f7f7;
    font-family: 'Gotham Narrow SSm','Helvetica Neue',Helvetica,sans-serif;
    font-size: 16px;
    color: #222;
    line-height: 1.4em;
    margin: 0;
    padding: 0;
  }
  body {
    padding: 1rem;
  }
  a { color: <%= $openapi_spec_renderer_theme_color %>; text-decoration: underline; word-break: break-word; }
  a:hover { text-decoration: none; }
  h1, h2, h3, h4 { font-family: Verdana; color: #403f41; font-weight: bold; line-height: 1.2em; margin: 1em 0; padding-top: 0.4rem; }
  h1 a, h2 a, h3 a, h4 a { text-decoration: none; color: inherit; }
  h1 a:hover, h2 a:hover, h3 a:hover, h4 a:hover { text-decoration: underline; }
  h1 { font-size: 2.4em; }

  h1 { margin-top: 0; padding-top: 1em; }
  h2 { font-size: 1.8em; border-bottom: 2px solid #cfd4c5; }
  h3 { font-size: 1.4em; }
  h4 { font-size: 1.1em; }
  table {
    margin: 0em -0.4rem;
    width: 100%;
    border-collapse: collapse;
  }
  td, th {
    vertical-align: top;
    text-align: left;
    padding: 0.4rem;
  }
  th {
    font-weight: bold;
    border-bottom: 1px solid #ccc;
  }
  td p, th p {
    margin: 0;
  }
  ol,
  ul {
    margin: 0;
    padding: 0 1.5em;
  }
  ul.unstyled {
    list-style: none;
    padding: 0;
  }
  p {
    margin: 1em 0;
  }

  .json-container,
  pre {
    background: #f1f3ed;
    font-size: 0.9rem;
    line-height: 1.4em;
    letter-spacing: -0.02em;
    border-left: 4px solid <%= $openapi_spec_renderer_theme_color %>;
    padding: 0.5em;
    margin: 1rem 0rem;
    overflow: auto;
  }

  .openapi-nav a {
    text-decoration: none;
    line-height: 1.5rem;
    white-space: nowrap;
  }

  .openapi-logo { display: none; }
  .openapi-nav ol { margin: 0.2rem 0 0.5rem 0; }
  .openapi-up-button { display: none; }

  .openapi-container { max-width: 50rem; margin: 0 auto; }
  p.version { margin: -1rem 0 2em 0; }
  p.op-deprecated { color: #c00; }

  h3.op-path { margin-top: 2em; padding: 0.5rem 0 0 0; }
  h2 + h3.op-path { margin-top: 1em; }

  .json-item .json-item {
    border: 0;
    padding: 0;
    margin: 0;
    margin-left: 0.4rem;
    padding-left: 0.4rem;
  }

  .json-array > .json-item > .json-key,
  .json-array > .json-item > .json-key + .json-type { display: none; }
  .json-array > .json-item > .json-string:before { content: '- '; color: #222; font-weight: bold; }
  .json-boolean, .json-number, .json-string { color: <%= $openapi_spec_renderer_theme_color %>; font-weight: 500; }
  .json-key:after { content: ': '; color: #222; }
  .json-null { color: #222; }
  .json-type { color: #c5a138; display: none; }

  .json-item:hover > .json-type { display: inline; }
  .json-container > .json-type { display: none !important; }
  .json-container > div > .json-item { padding: 0; margin: 0; }

  @media only screen {
    .openapi-up-button {
      background: <%= $openapi_spec_renderer_theme_color %>;
      color: #f2f3ed;
      font-weight: bold;
      font-size: 1.2rem;
      line-height: 1.5em;
      text-align: center;
      border: 0;
      box-shadow: 0 0 3px 3px rgba(0, 0, 0, 0.2);
      border-radius: 50%;
      padding-top: 0.3em;
      width: 2.1em;
      height: 2.1em;
      opacity: 0;
      position: fixed;
      bottom: 1.5rem;
      left: calc(50vw + 31rem);
      transition: background 0.25s ease-in-out, opacity 0.25s ease-in-out;
      cursor: pointer;
    }

    .openapi-up-button:hover {
      background: #2c520f;
    }

    .openapi-up-button.is-visible {
      opacity: 0.9;
    }
  }

  @media only screen and (max-width: 70rem) {
    .openapi-up-button {
      left: auto;
      right: 1rem;
    }
  }

  @media only screen and (min-width: 60rem) {
    body {
      padding: 0;
    }

    .openapi-up-button {
      display: block;
    }

    .openapi-container {
      max-width: 70rem;
    }

    .openapi-nav {
      padding: 1.4rem 0 3rem 1rem;
      width: 18rem;
      height: 100vh;
      overflow: auto;
      -webkit-overflow-scrolling: touch;
      position: fixed;
      top: 0;
    }

    .openapi-logo {
      display: block;
      margin-bottom: 1rem;
    }

    .openapi-logo img {
      max-height: 100px;
      max-width 100%;
    }

    .openapi-nav ol {
      list-style: none;
      padding: 0;
      margin: 0;
    }

    .openapi-nav li a {
      margin: -0.1rem -0.2rem;
      padding: 0.1rem 0.4rem;
      display: block;
    }

    .openapi-nav li a:hover {
      background: #e5e8df;
      text-decoration: none;
    }

    .openapi-nav > ol > li > a {
      color: #403f41;
      font-weight: bold;
      font-size: 1.1rem;
      line-height: 1.8em;
    }

    .openapi-nav li.is-active a {
      background: #e3e6de;
    }

    .openapi-nav .method {
      font-size: 0.8rem;
      color: #222;
      width: auto;
    }

    .openapi-footer,
    .openapi-header,
    .openapi-spec {
      margin-left: 21rem;
      margin-right: 1rem;
    }

    .openapi-footer {
      border-top: 4px solid #cfd4c5;
      padding-top: 2.5rem;
      margin-top: 4rem;
    }

    #about {
      height: 1px;
      overflow: hidden;
      position: absolute;
      top: -10rem;
      opacity: 0;
    }
  }
</style>
@@ mojolicious/plugin/openapi/logo.png (base64)
iVBORw0KGgoAAAANSUhEUgAAAMgAAAA5CAMAAABESJQQAAAABGdBTUEAALGPC/xhBQAAACBjSFJN
AAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAC+lBMVEVHcExXYExNTE5GREZH
RkhLSUxZXFMAAElLSkxEQ0VDQkRDQkNDQkRDQkRFRUZMSk1LSkxJR0pRU09DQkREQ0VOT0tUVFFE
Q0RHRkd8gHxNS05CQUNUVFF2tk95qlByqkt2rU5vp0hfZ09ZZkdLS0xDQkRCQUN2qU5wqUptp0Zt
p0ZupkZspkRwqEhLXDJNXDNOXTNOXTROXTRSYDdYZz5nkVNEQ0VNTE9wqEpup0ZrpUNupEZQXzVM
WzFSYThSYjhgYVyArlZwp0htpkZNXDFNXDNRYDdeZk1RUU1EQ0VDQkSi01KVyEhtp0VSYDdCQUNL
SkuWyT+XykJ0q0xNXDJYXVBYWlVFREZFREZCQkOtx22YykWWyUCVyD2VyD6Wx0ltpkZMS05FREZJ
SEmXykKWyUB8rE1NXDNFREZCQUNGRUdFREZfX19XZztOXTRth0KWyUGUyD2XykRRYjdOTU9PXTRw
iUWVyD+Mu0xtp0dNXDJPXjVMS01PXjSWyUGYykN2qlBspkRRUFJbXlhPXjSUyT5PTlBRYDdYZz1N
XDFspkRRYTdNXDFSXj1tg0CVyT6Zy0VaX1JEQ0VQXzZDQURSYjlxoU1wqElSYDdSYTmXykdSYThT
YTlJSEpJR0lCQUNJSEpEREVRUVNKSEtYWFhPTlFOTlBNTE1GRkdISElHR0lxcHJxbXFEREVcXFVh
YGJycXJ7e354eHxsa25JSUpFQ0Y/PkpBQUNIR0hAQEdIR0lKSUtHRkiJrmVEQUSenpyhs46Vm4Nv
qElwqUpGRUdEQ0VIR0lKSEpHRkiWykGVyD5CQUNCQUNHRkdJSUqn1l6Vxklvp0dTU1VBQUVEQERE
Q0VKSkyYy0hrpkNfX2JGRUdPT1B0pk9rpkRHRkhFREVJSEtEREVLSkyVyD+WyUB1pFBZWVqVxU91
olBup0hnZ2ptpkZDQ0NKSkuXyUN0plBMWzKXxkyXyERXV1lKSUtTYThPTVBKSktDQUNCQUNrpUNM
WzGUyD3///+AqxLvAAAA+XRSTlMAE0FicjwRAkfV7/j97cgzYVkE8eEqDLmiAiTkIgoTGi0yDi43
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
KzAwOjAw+374IAAAAABJRU5ErkJggg==
