package Mojolicious::Plugin::OpenAPI::SpecRenderer;
use Mojo::Base -base;

use Mojo::JSON;

use constant DEBUG    => $ENV{MOJO_OPENAPI_DEBUG} || 0;
use constant MARKDOWN => eval 'require Text::Markdown;1';

sub register {
  my ($self, $app, $openapi, $config) = @_;

  if ($config->{render_specification} // 1) {
    my $spec_route = $openapi->route->get('/')->to(cb => sub { shift->openapi->render_spec });
    my $name = $config->{spec_route_name} || $openapi->validator->get('/x-mojo-name');
    $spec_route->name($name) if $name;
    push @{$app->renderer->classes}, __PACKAGE__ unless $app->{'openapi.render_specification'}++;
  }

  if ($config->{render_specification_for_paths} // 1) {
    $app->plugins->once(openapi_routes_added => sub { $self->_add_documentation_routes(@_) });
  }

  $app->helper('openapi.render_spec' => \&_render_spec);
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
    $doc_route->to(cb => sub { _render_spec(shift, $openapi_path) });
    $doc_route->name(join '_', $route->name, 'openapi_documentation') if $route->name;
    warn "[OpenAPI] Add route options $route_path (@{[$doc_route->name // '']})\n" if DEBUG;
  }
}

sub _markdown {
  return Mojo::ByteStream->new(MARKDOWN ? Text::Markdown::markdown($_[0]) : $_[0]);
}

sub _render_spec {
  my ($c, $path) = @_;
  my $self   = Mojolicious::Plugin::OpenAPI::_self($c);
  my $spec   = $self->{bundled} ||= $self->validator->bundle;
  my $format = $c->stash('format') || 'json';
  my $method = $c->param('method');

  if (defined $path) {
    $spec = $spec->{paths}{$path};
    unless (defined $method) {
      my $path_spec = $self->validator->get([paths => $path]);
      return $c->render(json => $path_spec) if $path_spec;
      return $c->render(json => undef, status => 404);
    }
    my $method_spec = $self->validator->get([paths => $path => $method]);
    return $c->render(json => undef, status => 404) unless $method_spec;
    local $method_spec->{parameters}
      = [@{$spec->{parameters} || []}, @{$method_spec->{parameters} || []}];
    return $c->render(json => $method_spec);
  }

  $spec = $self->validator->get([]);
  local $spec->{basePath} = $c->url_for($spec->{basePath});
  local $spec->{host}     = $c->req->url->to_abs->host_port;

  return $c->render(json => $spec) unless $format eq 'html';
  return $c->render(
    handler   => 'ep',
    template  => 'mojolicious/plugin/openapi/layout',
    esc       => sub { local $_ = shift; s/\W/-/g; $_ },
    markdown  => \&_markdown,
    serialize => \&_serialize,
    spec      => $spec,
    X_RE      => qr{^x-},
  );
}

sub _serialize { Mojo::JSON::encode_json(@_) }

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI::SpecRenderer - Render OpenAPI specification

=head1 SYNOPSIS

  $app->plugin(OpenAPI => {
    plugins                        => [qw(+SpecRenderer)],
    render_specification           => 1,
    render_specification_for_paths => 1,
  });

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI::SpecRenderer> will enable
L<Mojolicious::Plugin::OpenAPI> to render the specification in both HTML and
JSON format.

The human readable format focus on making the documentation printable, so you
can easily share it with third parties as a PDF. If this documentation format
is too basic or has missing information, then please
L<report in|https://github.com/jhthorsen/mojolicious-plugin-openapi/issues>
suggestions for enhancements.

=head1 HELPERS

=head2 openapi.render_spec

  $c = $c->openapi->render_spec;
  $c = $c->openapi->render_spec($openapi_path);
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

=head1 SEE ALSO

L<Mojolicious::Plugin::OpenAPI>

=cut

__DATA__
@@ mojolicious/plugin/openapi/header.html.ep
<h1 id="title"><%= $spec->{info}{title} || 'No title' %></h1>
<p class="version"><span>Version</span> <span class="version"><%= $spec->{info}{version} %></span></p>

%= include "mojolicious/plugin/openapi/toc"

% if ($spec->{info}{description}) {
<h2 id="description"><a href="#title">Description</a></h2>
<div class="description">
  %== $markdown->($spec->{info}{description})
</div>
% }

% if ($spec->{info}{termsOfService}) {
<h2 id="terms-of-service"><a href="#title">Terms of service</a></h2>
<p class="terms-of-service">
  %= $spec->{info}{termsOfService}
</p>
% }
@@ mojolicious/plugin/openapi/footer.html.ep
% my $contact = $spec->{info}{contact};
% my $license = $spec->{info}{license};
<h2 id="license"><a href="#title">License</a></h2>
% if ($license->{name}) {
<p class="license"><a href="<%= $license->{url} || '' %>"><%= $license->{name} %></a></p>
% } else {
<p class="no-license">No license specified.</p>
% }
<h2 id="contact"<a href="#title">Contact information</a></h2>
% if ($contact->{email}) {
<p class="contact-email"><a href="mailto:<%= $contact->{email} %>"><%= $contact->{email} %></a></p>
% }
% if ($contact->{url}) {
<p class="contact-url"><a href="mailto:<%= $contact->{url} %>"><%= $contact->{url} %></a></p>
% }
@@ mojolicious/plugin/openapi/human.html.ep
% if ($spec->{summary}) {
<p class="spec-summary"><%= $spec->{summary} %></p>
% }
% if ($spec->{description}) {
<div class="spec-description"><%== $markdown->($spec->{description}) %></div>
% }
% if (!$spec->{description} and !$spec->{summary}) {
<p class="op-summary op-doc-missing">This resource is not documented.</p>
% }
@@ mojolicious/plugin/openapi/parameters.html.ep
% my $has_parameters = @{$op->{parameters} || []};
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
% for my $p (@{$op->{parameters} || []}) {
  % $body = $p->{schema} if $p->{in} eq 'body';
  <tr>
    % if ($spec->{parameters}{$p->{name}}) {
      <td><a href="#ref-parameters-<%= $esc->($p->{name}) %>"><%= $p->{name} %></a></td>
    % } else {
      <td><%= $p->{name} %></td>
    % }
    <td><%= $p->{in} %></td>
    <td><%= $p->{type} %></td>
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
@@ mojolicious/plugin/openapi/response.html.ep
% for my $code (sort keys %{$op->{responses}}) {
  % next if $code =~ $X_RE;
  % my $res = $op->{responses}{$code};
<h4 class="op-response">Response <%= $code %></h3>
%= include "mojolicious/plugin/openapi/human", spec => $res
<pre class="op-response"><%= $serialize->($res->{schema}) %></pre>
% }
@@ mojolicious/plugin/openapi/resource.html.ep
<h3 id="op-<%= lc $method %><%= $esc->($path) %>" class="op-path <%= $op->{deprecated} ? "deprecated" : "" %>"><a href="#title"><%= uc $method %> <%= $spec->{basePath} %><%= $path %></a></h3>
% if ($op->{deprecated}) {
<p class="op-deprecated">This resource is deprecated!</p>
% }
% if ($op->{operationId}) {
<p class="op-id"><b>Operation ID:</b> <span><%= $op->{operationId} %></span></p>
% }
%= include "mojolicious/plugin/openapi/human", spec => $op
%= include "mojolicious/plugin/openapi/parameters", op => $op
%= include "mojolicious/plugin/openapi/response", op => $op
@@ mojolicious/plugin/openapi/references.html.ep
% use Mojo::ByteStream 'b';
<h2 id="references"><a href="#title">References</a></h2>
% for my $key (sort { $a cmp $b } keys %{$spec->{definitions} || {}}) {
  % next if $key =~ $X_RE;
  <h3 id="ref-definitions-<%= lc $esc->($key) %>"><a href="#title">#/definitions/<%= $key %></a></h3>
  <pre class="ref"><%= $serialize->($spec->{definitions}{$key}) %></pre>
% }
% for my $key (sort { $a cmp $b } keys %{$spec->{parameters} || {}}) {
  % next if $key =~ $X_RE;
  % my $item = $spec->{parameters}{$key};
  <h3 id="ref-parameters-<%= lc $esc->($key) %>"><a href="#title">#/parameters/<%= $key %> - "<%= $item->{name} %>"</a></h3>
  <p><%= $item->{description} || 'No description.' %></p>
  <ul>
    <li>In: <%= $item->{in} %></li>
    <li>Type: <%= $item->{type} %><%= $item->{format} ? " / $item->{format}" : "" %><%= $item->{pattern} ? " / $item->{pattern}" : ""%></li>
    % if ($item->{exclusiveMinimum} || $item->{exclusiveMaximum} || $item->{minimum} || $item->{maximum}) {
      <li>
        Min / max:
        <%= $item->{exclusiveMinimum} ? "$item->{exclusiveMinimum} <" : $item->{minimum} ? "$item->{minimum} <=" : b("&infin; <=") %>
        value
        <%= $item->{exclusiveMaximum} ? "< $item->{exclusiveMaximum}" : $item->{maximum} ? "<= $item->{maximum}" : b("<= &infin;") %>
      </li>
    % }
    % if ($item->{minLength} || $item->{maxLength}) {
      <li>
        Min / max:
        <%= $item->{minLength} ? "$item->{minLength} <=" : b("&infin; <=") %>
        length
        <%= $item->{maxLength} ? "<= $item->{maxLength}" : b("<= &infin;") %>
      </li>
    % }
    % if ($item->{minItems} || $item->{maxItems}) {
      <li>
        Min / max:
        <%= $item->{minItems} ? "$item->{minItems} <=" : b("&infin; <=") %>
        items
        <%= $item->{maxItems} ? "<= $item->{maxItems}" : b("<= &infin;") %>
      </li>
    % }
    % for my $k (qw(collectionFormat uniqueItems multipleOf enum)) {
      % next unless $item->{$k};
      <li><%= ucfirst $k %>: <%= ref $item->{$k} ? $serialize->($item->{$k}) : $item->{$k} %></li>
    % }
    <li>Required: <%= $item->{required} ? 'Yes.' : 'No.' %></li>
    <li><%= defined $item->{default} ? "Default: " . $serialize->($item->{default}) : 'No default value.' %></li>
  </ul>
  % for my $k (qw(items schema)) {
    % next unless $item->{$k};
    <pre class="ref"><%= $serialize->($item->{$k}) %></pre>
  % }
% }

@@ mojolicious/plugin/openapi/resources.html.ep
<h2 id="resources"><a href="#title">Resources</a></h2>

% my $schemes = $spec->{schemes} || ["http"];
% my $url = Mojo::URL->new("http://$spec->{host}");
<h3 id="base-url"><a href="#title">Base URL</a></h3>
<ul class="unstyled">
% for my $scheme (@$schemes) {
  % $url->scheme($scheme);
  <li><a href="<%= $url %>"><%= $url %></a></li>
% }
</ul>

% for my $path (sort { length $a <=> length $b } keys %{$spec->{paths}}) {
  % next if $path =~ $X_RE;
  % for my $http_method (sort keys %{$spec->{paths}{$path}}) {
    % next if $http_method =~ $X_RE or $http_method eq 'parameters';
    % my $op = $spec->{paths}{$path}{$http_method};
    %= include "mojolicious/plugin/openapi/resource", method => $http_method, op => $op, path => $path
  % }
% }
@@ mojolicious/plugin/openapi/toc.html.ep
<ul id="toc">
  % if ($spec->{info}{description}) {
  <li><a href="#description">Description</a></li>
  % }
  % if ($spec->{info}{termsOfService}) {
  <li><a href="#terms-of-service">Terms of service</a></li>
  % }
  <li>
    <a href="#resources">Resources</a>
    <ul>
    % for my $path (sort { length $a <=> length $b } keys %{$spec->{paths}}) {
      % next if $path =~ $X_RE;
      % for my $method (sort keys %{$spec->{paths}{$path}}) {
        % next if $method =~ $X_RE;
        <li><a href="#op-<%= lc $method %><%= $esc->($path) %>"><span class="method"><%= uc $method %></span> <%= $spec->{basePath} %><%= $path %></h3>
      % }
    % }
    </ul>
  </li>
  <li>
    <a href="#references">References</a>
    <ul>
    % for my $key (sort { $a cmp $b } keys %{$spec->{definitions} || {}}) {
      % next if $key =~ $X_RE;
      <li><a href="#ref-definitions-<%= lc $esc->($key) %>">#/definitions/<%= $key %></a></li>
    % }
    % for my $key (sort { $a cmp $b } keys %{$spec->{parameters} || {}}) {
      % next if $key =~ $X_RE;
      <li><a href="#ref-parameters-<%= lc $esc->($key) %>">#/parameters/<%= $key %></a></li>
    % }
    </ul>
  </li>
  <li><a href="#license">License</a></li>
  <li><a href="#contact">Contact</a></li>
</ul>
@@ mojolicious/plugin/openapi/layout.html.ep
<!doctype html>
<html lang="en">
<head>
  <title><%= $spec->{info}{title} || 'No title' %></title>
  <style>
    body {
      font-family: 'Gotham Narrow SSm','Helvetica Neue',Helvetica,sans-serif;
      font-size: 16px;
      margin: 3em;
      padding: 0;
      color: #222;
      line-height: 1.4em;
    }
    a {
      color: #225;
      text-decoration: underline;
    }
    h1, h2, h3, h4 { font-weight: bold; margin: 1em 0; }
    h1 a, h2 a, h3 a, h4 a { text-decoration: none; color: #222; }
    h1 { font-size: 2em; }
    h2 { font-size: 1.6em; margin-top: 2em; }
    h3 { font-size: 1.2em; }
    h4 { font-size: 1.1em; }
    table {
      margin: 0em -0.5em;
      width: 100%;
      border-collapse: collapse;
    }
    td, th {
      vertical-align: top;
      text-align: left;
      padding: 0.5em;
    }
    th {
      font-weight: bold;
      border-bottom: 1px solid #ccc;
    }
    td p, th p {
      margin: 0;
    }
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
    pre {
      background: #f3f3f3;
      font-size: 0.9rem;
      line-height: 1.2em;
      letter-spacing: -0.02em;
      border: 1px solid #ddd;
      padding: 0.5em;
      margin: 1em -0.5em;
      overflow: auto;
    }
    #toc a { text-decoration: none; display: block; }
    #toc .method { display: inline-block; width: 7em; }
    div.container { max-width: 50em; margin: 0 auto; }
    p.version { color: #666; margin: -0.5em 0 2em 0; }
    p.op-deprecated { color: #c00; }
    h3.op-path { margin-top: 3em; }
    .container > h3.op-path { margin-top: 1em; }
    .renderjson .disclosure { display: none; }
    .renderjson .syntax     { color: #002b36; }
    .renderjson .string     { color: #073642; }
    .renderjson .number     { color: #2aa198; }
    .renderjson .boolean    { color: #d33682; }
    .renderjson .key        { color: #0e6fb3; }
    .renderjson .keyword    { color: #b58900; }
  </style>
</head>
<body>
<div class="container">
  %= include "mojolicious/plugin/openapi/header"
  %= include "mojolicious/plugin/openapi/resources"
  %= include "mojolicious/plugin/openapi/references"
  %= include "mojolicious/plugin/openapi/footer"
</div>
<script>
var module,window,define,renderjson=function(){function n(a,u,c,p,f){var y=c?"":u,_=function(n,o,a,u,c){var _,d=l(u),h=function(){_||e(d.parentNode,_=r(c(),i(f.hide,"disclosure",function(){_.style.display="none",d.style.display="inline"}))),_.style.display="inline",d.style.display="none"};e(d,i(f.show,"disclosure",h),t(u+" syntax",n),i(o,null,h),t(u+" syntax",a));var g=e(l(),s(y.slice(0,-1)),d);return p>0&&"string"!=u&&h(),g};return null===a?t(null,y,"keyword","null"):void 0===a?t(null,y,"keyword","undefined"):"string"==typeof a&&a.length>f.max_string_length?_('"',a.substr(0,f.max_string_length)+" ...",'"',"string",function(){return e(l("string"),t(null,y,"string",JSON.stringify(a)))}):"object"!=typeof a||[Number,String,Boolean,Date].indexOf(a.constructor)>=0?t(null,y,typeof a,JSON.stringify(a)):a.constructor==Array?0==a.length?t(null,y,"array syntax","[]"):_("["," ... ","]","array",function(){for(var r=e(l("array"),t("array syntax","[",null,"\n")),o=0;o<a.length;o++)e(r,n(f.replacer.call(a,o,a[o]),u+"  ",!1,p-1,f),o!=a.length-1?t("syntax",","):[],s("\n"));return e(r,t(null,u,"array syntax","]")),r}):o(a,f.property_list)?t(null,y,"object syntax","{}"):_("{","...","}","object",function(){var r=e(l("object"),t("object syntax","{",null,"\n"));for(var o in a)var i=o;var c=f.property_list||Object.keys(a);f.sort_objects&&(c=c.sort());for(var y in c)(o=c[y])in a&&e(r,t(null,u+"  ","key",'"'+o+'"',"object syntax",": "),n(f.replacer.call(a,o,a[o]),u+"  ",!0,p-1,f),o!=i?t("syntax",","):[],s("\n"));return e(r,t(null,u,"object syntax","}")),r})}var t=function(){for(var n=[];arguments.length;)n.push(e(l(Array.prototype.shift.call(arguments)),s(Array.prototype.shift.call(arguments))));return n},e=function(){for(var n=Array.prototype.shift.call(arguments),t=0;t<arguments.length;t++)arguments[t].constructor==Array?e.apply(this,[n].concat(arguments[t])):n.appendChild(arguments[t]);return n},r=function(n,t){return n.insertBefore(t,n.firstChild),n},o=function(n,t){var e=t||Object.keys(n);for(var r in e)if(Object.hasOwnProperty.call(n,e[r]))return!1;return!0},s=function(n){return document.createTextNode(n)},l=function(n){var t=document.createElement("span");return n&&(t.className=n),t},i=function(n,t,e){var r=document.createElement("a");return t&&(r.className=t),r.appendChild(s(n)),r.href="#",r.onclick=function(n){return e(),n&&n.stopPropagation(),!1},r},a=function t(r){var o=Object.assign({},t.options);o.replacer="function"==typeof o.replacer?o.replacer:function(n,t){return t};var s=e(document.createElement("pre"),n(r,"",!1,o.show_to_level,o));return s.className="renderjson",s};return a.set_icons=function(n,t){return a.options.show=n,a.options.hide=t,a},a.set_show_to_level=function(n){return a.options.show_to_level="string"==typeof n&&"all"===n.toLowerCase()?Number.MAX_VALUE:n,a},a.set_max_string_length=function(n){return a.options.max_string_length="string"==typeof n&&"none"===n.toLowerCase()?Number.MAX_VALUE:n,a},a.set_sort_objects=function(n){return a.options.sort_objects=n,a},a.set_replacer=function(n){return a.options.replacer=n,a},a.set_property_list=function(n){return a.options.property_list=n,a},a.set_show_by_default=function(n){return a.options.show_to_level=n?Number.MAX_VALUE:0,a},a.options={},a.set_icons("⊕","⊖"),a.set_show_by_default(!1),a.set_sort_objects(!1),a.set_max_string_length("none"),a.set_replacer(void 0),a.set_property_list(void 0),a}();define?define({renderjson:renderjson}):(module||{}).exports=(window||{}).renderjson=renderjson;
(function(w, d) {
  renderjson.set_show_to_level("all");
  renderjson.set_sort_objects(true);
  renderjson.set_max_string_length(100);

  var els = d.querySelectorAll("pre");
  for (var i = 0; i < els.length; i++) {
    els[i].parentNode.replaceChild(renderjson(JSON.parse(els[i].innerText)), els[i]);
  }

  els = d.querySelectorAll(".key");
  for (var i = 0; i < els.length; i++) {
    if (els[i].textContent != '"$ref"') continue;
    var link = els[i].nextElementSibling;
    while (link = link.nextElementSibling) {
      if (!link.className || !link.className.match(/\bstring\b/)) continue;
      var a = d.createElement("a");
      var href = link.textContent.replace(/"/g, "");
      a.className = link.className;
      a.textContent = link.textContent;
      a.href = href.match(/^#/) ? "#ref-" + href.replace(/\W/g, "-").substring(2).toLowerCase() : href;
      link.parentNode.replaceChild(a, link);
    }
  }
})(window, document);
</script>
</body>
</html>
