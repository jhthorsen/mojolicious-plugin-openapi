# NAME

Mojolicious::Plugin::OpenAPI - OpenAPI / Swagger plugin for Mojolicious

# SYNOPSIS

    # It is recommended to use Mojolicious::Plugin::OpenAPI with a "full app".
    # See the links after this example for more information.
    use Mojolicious::Lite;

    # Because the route name "echo" matches the "x-mojo-name", this route
    # will be moved under "basePath", resulting in "POST /api/echo"
    post "/echo" => sub {

      # Validate input request or return an error document
      my $c = shift->openapi->valid_input or return;

      # Generate some data
      my $data = {body => $c->req->json};

      # Validate the output response and render it to the user agent
      # using a custom "openapi" handler.
      $c->render(openapi => $data);
    }, "echo";

    # Load specification and start web server
    plugin OpenAPI => {url => "data:///swagger.yaml"};
    app->start;

    __DATA__
    @@ swagger.yaml
    swagger: "2.0"
    info: { version: "0.8", title: "Echo Service" }
    schemes: ["https"]
    basePath: "/api"
    paths:
      /echo:
       post:
         x-mojo-name: "echo"
         parameters:
         - { in: "body", name: "body", schema: { type: "object" } }
         responses:
           200:
             description: "Echo response"
             schema: { type: "object" }

See [Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv2) or
[Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv3](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv3) for more in depth
information about how to use [Mojolicious::Plugin::OpenAPI](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI) with a "full app".
Even with a "lite app" it can be very useful to read those guides.

Looking at the documentation for
["x-mojo-to" in Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv2#x-mojo-to) can be especially
useful. (The logic is the same for OpenAPIv2 and OpenAPIv3)

# DESCRIPTION

[Mojolicious::Plugin::OpenAPI](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI) is [Mojolicious::Plugin](https://metacpan.org/pod/Mojolicious%3A%3APlugin) that add routes and
input/output validation to your [Mojolicious](https://metacpan.org/pod/Mojolicious) application based on a OpenAPI
(Swagger) specification. This plugin supports both version [2.0](#schema) and
[3.x](#schema), though 3.x _might_ have some missing features.

Have a look at the ["SEE ALSO"](#see-also) for references to plugins and other useful
documentation.

Please report in [issues](https://github.com/jhthorsen/json-validator/issues)
or open pull requests to enhance the 3.0 support.

# HELPERS

## openapi.spec

    $hash = $c->openapi->spec($json_pointer)
    $hash = $c->openapi->spec("/info/title")
    $hash = $c->openapi->spec;

Returns the OpenAPI specification. A JSON Pointer can be used to extract a
given section of the specification. The default value of `$json_pointer` will
be relative to the current operation. Example:

    {
      "paths": {
        "/pets": {
          "get": {
            // This datastructure is returned by default
          }
        }
      }
    }

## openapi.validate

    @errors = $c->openapi->validate;

Used to validate a request. `@errors` holds a list of
[JSON::Validator::Error](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3AError) objects or empty list on valid input.

Note that this helper is only for customization. You probably want
["openapi.valid\_input"](#openapi-valid_input) in most cases.

## openapi.valid\_input

    $c = $c->openapi->valid_input;

Returns the [Mojolicious::Controller](https://metacpan.org/pod/Mojolicious%3A%3AController) object if the input is valid or
automatically render an error document if not and return false. See
["SYNOPSIS"](#synopsis) for example usage.

# HOOKS

[Mojolicious::Plugin::OpenAPI](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI) will emit the following hooks on the
[application](https://metacpan.org/pod/Mojolicious) object.

## openapi\_routes\_added

Emitted after all routes have been added by this plugin.

    $app->hook(openapi_routes_added => sub {
      my ($openapi, $routes) = @_;

      for my $route (@$routes) {
        ...
      }
    });

This hook is EXPERIMENTAL and subject for change.

# RENDERER

This plugin register a new handler called `openapi`. The special thing about
this handler is that it will validate the data before sending it back to the
user agent. Examples:

    $c->render(json => {foo => 123});    # without validation
    $c->render(openapi => {foo => 123}); # with validation

This handler will also use ["renderer"](#renderer) to format the output data. The code
below shows the default ["renderer"](#renderer) which generates JSON data:

    $app->plugin(
      OpenAPI => {
        renderer => sub {
          my ($c, $data) = @_;
          return Mojo::JSON::encode_json($data);
        }
      }
    );

# ATTRIBUTES

## route

    $route = $openapi->route;

The parent [Mojolicious::Routes::Route](https://metacpan.org/pod/Mojolicious%3A%3ARoutes%3A%3ARoute) object for all the OpenAPI endpoints.

## validator

    $jv = $openapi->validator;

Holds either a [JSON::Validator::Schema::OpenAPIv2](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3ASchema%3A%3AOpenAPIv2) or a
[JSON::Validator::Schema::OpenAPIv3](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3ASchema%3A%3AOpenAPIv3) object.

# METHODS

## register

    $openapi = $openapi->register($app, \%config);
    $openapi = $app->plugin(OpenAPI => \%config);

Loads the OpenAPI specification, validates it and add routes to
[$app](https://metacpan.org/pod/Mojolicious). It will also set up ["HELPERS"](#helpers) and adds a
[before\_render](https://metacpan.org/pod/Mojolicious#before_render) hook for auto-rendering of error
documents. The return value is the object instance, which allow you to access
the ["ATTRIBUTES"](#attributes) after you load the plugin.

`%config` can have:

### coerce

See ["coerce" in JSON::Validator](https://metacpan.org/pod/JSON%3A%3AValidator#coerce) for possible values that `coerce` can take.

Default: booleans,numbers,strings

The default value will include "defaults" in the future, once that is stable enough.

### default\_response

Instructions for
["add\_default\_response\_schema" in JSON::Validator::Schema::OpenAPIv2](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3ASchema%3A%3AOpenAPIv2#add_default_response_schema). (Also used
for OpenAPIv3)

### format

Set this to a default list of file extensions that your API accepts. This value
can be overwritten by
["x-mojo-to" in Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv2#x-mojo-to).

This config parameter is EXPERIMENTAL and subject for change.

### log\_level

`log_level` is used when logging invalid request/response error messages.

Default: "warn".

### op\_spec\_to\_route

`op_spec_to_route` can be provided if you want to add route definitions
without using "x-mojo-to". Example:

    $app->plugin(OpenAPI => {op_spec_to_route => sub {
      my ($plugin, $op_spec, $route) = @_;

      # Here are two ways to customize where to dispatch the request
      $route->to(cb => sub { shift->render(openapi => ...) });
      $route->to(ucfirst "$op_spec->{operationId}#handle_request");
    }});

This feature is EXPERIMENTAL and might be altered and/or removed.

### plugins

A list of OpenAPI classes to extend the functionality. Default is:
[Mojolicious::Plugin::OpenAPI::Cors](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3ACors),
[Mojolicious::Plugin::OpenAPI::SpecRenderer](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3ASpecRenderer) and
[Mojolicious::Plugin::OpenAPI::Security](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3ASecurity).

    $app->plugin(OpenAPI => {plugins => [qw(+Cors +SpecRenderer +Security)]});

You can load your own plugins by doing:

    $app->plugin(OpenAPI => {plugins => [qw(+SpecRenderer My::Cool::OpenAPI::Plugin)]});

### renderer

See ["RENDERER"](#renderer).

### route

`route` can be specified in case you want to have a protected API. Example:

    $app->plugin(OpenAPI => {
      route => $app->routes->under("/api")->to("user#auth"),
      url   => $app->home->rel_file("cool.api"),
    });

### skip\_validating\_specification

Used to prevent calling ["errors" in JSON::Validator::Schema::OpenAPIv2](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3ASchema%3A%3AOpenAPIv2#errors) for the
specification.

### spec\_route\_name

Name of the route that handles the "basePath" part of the specification and
serves the specification. Defaults to "x-mojo-name" in the specification at
the top level.

### spec, url

See ["schema" in JSON::Validator](https://metacpan.org/pod/JSON%3A%3AValidator#schema) for the different `url` formats that is
accepted.

`spec` is an alias for "url", which might make more sense if your
specification is written in perl, instead of JSON or YAML.

Here are some common uses:

    $app->plugin(OpenAPI => {url  => $app->home->rel_file('openapi.yaml'));
    $app->plugin(OpenAPI => {url  => 'https://example.com/swagger.json'});
    $app->plugin(OpenAPI => {spec => JSON::Validator::Schema::OpenAPIv3->new(...)});
    $app->plugin(OpenAPI => {spec => {swagger => "2.0", paths => {...}, ...}});

### version\_from\_class

Can be used to overridden `/info/version` in the API specification, from the
return value from the `VERSION()` method in `version_from_class`.

Defaults to the current `$app`. This can be disabled by setting the
"version\_from\_class" to zero (0).

# AUTHORS

## Project Founder

Jan Henning Thorsen - `jhthorsen@cpan.org`

## Contributors

- Bernhard Graf <augensalat@gmail.com>
- Doug Bell <doug@preaction.me>
- Ed J <mohawk2@users.noreply.github.com>
- Henrik Andersen <hem@fibia.dk>
- Henrik Andersen <hem@hamster.dk>
- Ilya Rassadin <elcamlost@gmail.com>
- Jan Henning Thorsen <jan.henning@thorsen.pm>
- Jan Henning Thorsen <jhthorsen@cpan.org>
- Ji-Hyeon Gim <potatogim@gluesys.com>
- Joel Berger <joel.a.berger@gmail.com>
- Krasimir Berov <k.berov@gmail.com>
- Lars Thegler <lth@fibia.dk>
- Lee Johnson <lee@givengain.ch>
- Linn-Hege Kristensen <linn-hege@stix.no>
- Manuel <manuel@mausz.at>
- Martin Renvoize <martin.renvoize@ptfs-europe.com>
- Mohammad S Anwar <mohammad.anwar@yahoo.com>
- Nick Morrott <knowledgejunkie@gmail.com>
- Renee <reb@perl-services.de>
- Roy Storey <kiwiroy@users.noreply.github.com>
- SebMourlhou <35918953+SebMourlhou@users.noreply.github.com>
- SebMourlhou <sebastien.mourlhou@justice.ge.ch>
- SebMourlhou <sebmourlhou@yahoo.fr>
- Søren Lund <sl@keycore.dk>
- Stephan Hradek <github@hradek.net>
- Stephan Hradek <stephan.hradek@eco.de>

# COPYRIGHT AND LICENSE

Copyright (C) Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

# SEE ALSO

- [Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv2)

    Guide for how to use this plugin with OpenAPI version 2.0 spec.

- [Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv3](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv3)

    Guide for how to use this plugin with OpenAPI version 3.0 spec.

- [Mojolicious::Plugin::OpenAPI::Cors](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3ACors)

    Plugin to add Cross-Origin Resource Sharing (CORS).

- [Mojolicious::Plugin::OpenAPI::Security](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3ASecurity)

    Plugin for handling security definitions in your schema.

- [Mojolicious::Plugin::OpenAPI::SpecRenderer](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3ASpecRenderer)

    Plugin for exposing your spec in human readable or JSON format.

- [https://www.openapis.org/](https://www.openapis.org/)

    Official OpenAPI website.
