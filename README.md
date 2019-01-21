# NAME

Mojolicious::Plugin::OpenAPI - OpenAPI / Swagger plugin for Mojolicious

# SYNOPSIS

    use Mojolicious::Lite;

    # Will be moved under "basePath", resulting in "POST /api/echo"
    post "/echo" => sub {

      # Validate input request or return an error document
      my $c = shift->openapi->valid_input or return;

      # Generate some data
      my $data = {body => $c->validation->param("body")};

      # Validate the output response and render it to the user agent
      # using a custom "openapi" handler.
      $c->render(openapi => $data);
    }, "echo";

    # Load specification and start web server
    plugin OpenAPI => {url => "data:///api.json"};
    app->start;

    __DATA__
    @@ api.json
    {
      "swagger" : "2.0",
      "info" : { "version": "0.8", "title" : "Pets" },
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

See [Mojolicious::Plugin::OpenAPI::Guides::Tutorial](https://metacpan.org/pod/Mojolicious::Plugin::OpenAPI::Guides::Tutorial) for a tutorial on how to
write a "full" app with application class and controllers.

# DESCRIPTION

[Mojolicious::Plugin::OpenAPI](https://metacpan.org/pod/Mojolicious::Plugin::OpenAPI) is [Mojolicious::Plugin](https://metacpan.org/pod/Mojolicious::Plugin) that add routes and
input/output validation to your [Mojolicious](https://metacpan.org/pod/Mojolicious) application based on a OpenAPI
(Swagger) specification.

Have a look at the ["SEE ALSO"](#see-also) for references to more documentation, or jump
right to the [tutorial](https://metacpan.org/pod/Mojolicious::Plugin::OpenAPI::Guides::Tutorial).

Currently v2 is very well supported, while v3 should be considered higly
EXPERIMENTAL. Note that testing out v3 requires [YAML::XS](https://metacpan.org/pod/YAML::XS) to be installed.

Please report in [issues](https://github.com/jhthorsen/json-validator/issues)
or open pull requests to enhance the 3.0 support.

# AUTOMATIC RESOURCES

This module adds some extra resources automatically.

## Specification renderer

The specification in JSON or human rendered format can be retrieved by
requesting the `basePath`.

The human readable format focus on making the documentation printable, so you
can easily share it with third parties as a PDF. If this documentation format
is too basic or has missing information, then please
[report in](https://github.com/jhthorsen/mojolicious-plugin-openapi/issues)
suggestions for enhancements.

Examples:

    GET https://api.example.com/v1.json
    GET https://api.example.com/v1.html

## OPTIONS

Using the HTTP method "OPTIONS" will render the specification for a given path.

Examples:

    OPTIONS https://api.example.com/v1/users
    OPTIONS https://api.example.com/v1/users?method=get
    OPTIONS https://api.example.com/v1/users?method=post

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

## openapi.render\_spec

    $c = $c->openapi->render_spec;

Used to render the specification as either "html" or "json". Set the
["stash" in Mojolicious](https://metacpan.org/pod/Mojolicious#stash) variable "format" to change the format to render.

This helper is called by default, when accessing the "basePath" resource.

The "html" rendering needs improvement. Any help or feedback is much
appreciated.

## openapi.validate

    @errors = $c->openapi->validate;

Used to validate a request. `@errors` holds a list of
[JSON::Validator::Error](https://metacpan.org/pod/JSON::Validator::Error) objects or empty list on valid input.

Note that this helper is only for customization. You probably want
["openapi.valid\_input"](#openapi-valid_input) in most cases.

Validated input parameters will be copied to
`Mojolicious::Controller/validation`, which again can be extracted by the
"name" in the parameters list from the spec. Example:

    # specification:
    "parameters": [{"in": "body", "name": "whatever", "schema": {"type": "object"}}],

    # controller
    my $body = $c->validation->param("whatever");

## openapi.valid\_input

    $c = $c->openapi->valid_input;

Returns the [Mojolicious::Controller](https://metacpan.org/pod/Mojolicious::Controller) object if the input is valid or
automatically render an error document if not and return false. See
["SYNOPSIS"](#synopsis) for example usage.

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

    $route = $self->route;

The parent [Mojolicious::Routes::Route](https://metacpan.org/pod/Mojolicious::Routes::Route) object for all the OpenAPI endpoints.

## validator

    $jv = $self->validator;

Holds a [JSON::Validator::OpenAPI::Mojolicious](https://metacpan.org/pod/JSON::Validator::OpenAPI::Mojolicious) object.

# METHODS

## register

    $self = $self->register($app, \%config);
    $self = $app->plugin(OpenAPI => \%config);

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

See ["coerce" in JSON::Validator](https://metacpan.org/pod/JSON::Validator#coerce) for possible values that `coerce` can take.

Default: 1

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
["Default response schema" in Mojolicious::Plugin::OpenAPI::Guides::Tutorial](https://metacpan.org/pod/Mojolicious::Plugin::OpenAPI::Guides::Tutorial#Default-response-schema)
for more details.

### log\_level

`log_level` is used when logging invalid request/response error messages.

Default: "warn".

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

### spec\_route\_name

Name of the route that handles the "basePath" part of the specification and
serves the specification. Defaults to "x-mojo-name" in the specification at
the top level.

### url

See ["schema" in JSON::Validator](https://metacpan.org/pod/JSON::Validator#schema) for the different `url` formats that is
accepted.

`spec` is an alias for "url", which might make more sense if your
specification is written in perl, instead of JSON or YAML.

### version\_from\_class

Can be used to overriden `/info/version` in the API specification, from the
return value from the `VERSION()` method in `version_from_class`.

This will only have an effect if "version" is "0".

Defaults to the current `$app`.

# AUTHOR

Jan Henning Thorsen

# COPYRIGHT AND LICENSE

Copyright (C) 2016, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

# SEE ALSO

- [Mojolicious::Plugin::OpenAPI::Guides::Tutorial](https://metacpan.org/pod/Mojolicious::Plugin::OpenAPI::Guides::Tutorial)
- [Mojolicious::Plugin::OpenAPI::Security](https://metacpan.org/pod/Mojolicious::Plugin::OpenAPI::Security)
- [http://thorsen.pm/perl/programming/2015/07/05/mojolicious-swagger2.html](http://thorsen.pm/perl/programming/2015/07/05/mojolicious-swagger2.html).
- [OpenAPI specification](https://openapis.org/specification)
