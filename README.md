# NAME

Mojolicious::Plugin::OpenAPI - OpenAPI / Swagger plugin for Mojolicious

# SYNOPSIS

    use Mojolicious::Lite;

    # Will be moved under "basePath", resulting in "POST /api/echo"
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
    # Use "v3" instead of "v2" for "schema" if you are using OpenAPI v3
    # The plugin must be loaded *after* defining the routes in a Lite app
    plugin OpenAPI => {url => "data:///spec.json", schema => "v2"};
    app->start;

    __DATA__
    @@ spec.json
    {
      "swagger" : "2.0",
      "info" : { "version": "0.8", "title" : "Echo Service" },
      "schemes" : [ "http" ],
      "basePath" : "/api",
      "paths" : {
        "/echo" : {
          "post" : {
            "x-mojo-name" : "echo",
            "parameters" : [
              { "in": "body", "name": "body", "schema": { "type" : "object" } }
            ],
            "responses" : {
              "200": {
                "description": "Echo response",
                "schema": { "type": "object" }
              }
            }
          }
        }
      }
    }

See [Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv2) or
[Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv3](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv3) for tutorials on how to
write a "full" app with application class and controllers.

# IMPORTANT ANNOUNCEMENT

Next version of [Mojolicious::Plugin::OpenAPI](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI) will not be shipped with
[JSON::Validator::OpenAPI::Mojolicious](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3AOpenAPI%3A%3AMojolicious). Instead, it will depend on the new
[JSON::Validator::Schema::OpenAPIv2](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3ASchema%3A%3AOpenAPIv2) and [JSON::Validator::Schema::OpenAPIv3](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3ASchema%3A%3AOpenAPIv3)
modules.

The next version is available at
[https://github.com/jhthorsen/mojolicious-plugin-openapi/pull/160](https://github.com/jhthorsen/mojolicious-plugin-openapi/pull/160).

# DESCRIPTION

[Mojolicious::Plugin::OpenAPI](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI) is [Mojolicious::Plugin](https://metacpan.org/pod/Mojolicious%3A%3APlugin) that add routes and
input/output validation to your [Mojolicious](https://metacpan.org/pod/Mojolicious) application based on a OpenAPI
(Swagger) specification. This plugin supports both version [2.0](#schema) and
[3.x](#schema), though 3.x _might_ have some missing features.

Have a look at the ["SEE ALSO"](#see-also) for references to more documentation.

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

Holds a [JSON::Validator::OpenAPI::Mojolicious](https://metacpan.org/pod/JSON%3A%3AValidator%3A%3AOpenAPI%3A%3AMojolicious) object.

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

### allow\_invalid\_ref

The OpenAPI specification does not allow "$ref" at every level, but setting
this flag to a true value will ignore the $ref check.

Note that setting this attribute is discourage.

### coerce

See ["coerce" in JSON::Validator](https://metacpan.org/pod/JSON%3A%3AValidator#coerce) for possible values that `coerce` can take.

Default: booleans,numbers,strings

The default value will include "defaults" in the future, once that is stable enough.

### default\_response\_codes

A list of response codes that will get a `"$ref"` pointing to
"#/definitions/DefaultResponse", unless already defined in the spec.
"DefaultResponse" can be altered by setting ["default\_response\_name"](#default_response_name).

The default response code list is the following:

    400 | Bad Request           | Invalid input from client / user agent
    401 | Unauthorized          | Used by Mojolicious::Plugin::OpenAPI::Security
    404 | Not Found             | Route is not defined
    500 | Internal Server Error | Internal error or failed output validation
    501 | Not Implemented       | Route exists, but the action is not implemented

Note that more default codes might be added in the future if required by the
plugin.

### default\_response\_name

The name of the "definition" in the spec that will be used for
["default\_response\_codes"](#default_response_codes). The default value is "DefaultResponse". See
["Default response schema" in Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv2#Default-response-schema)
for more details.

### log\_level

`log_level` is used when logging invalid request/response error messages.

Default: "warn".

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

### schema

Can be used to set a different schema, than the default OpenAPI 2.0 spec.
Example values: "http://swagger.io/v2/schema.json", "v2" or "v3".

See also [Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv2) and
[Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv3](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AOpenAPI%3A%3AGuides%3A%3AOpenAPIv3).

### spec\_route\_name

Name of the route that handles the "basePath" part of the specification and
serves the specification. Defaults to "x-mojo-name" in the specification at
the top level.

### url

See ["schema" in JSON::Validator](https://metacpan.org/pod/JSON%3A%3AValidator#schema) for the different `url` formats that is
accepted.

`spec` is an alias for "url", which might make more sense if your
specification is written in perl, instead of JSON or YAML.

### version\_from\_class

Can be used to overridden `/info/version` in the API specification, from the
return value from the `VERSION()` method in `version_from_class`.

This will only have an effect if "version" is "0".

Defaults to the current `$app`.

# AUTHORS

Henrik Andersen

Ilya Rassadin

Jan Henning Thorsen

Joel Berger

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

    Plugin for exposing your spec in human readble or JSON format.

- [https://www.openapis.org/](https://www.openapis.org/)

    Official OpenAPI website.
