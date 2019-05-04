# You can install this project with curl -L http://cpanmin.us | perl - https://github.com/jhthorsen/mojolicious-plugin-openapi/archive/master.tar.gz
requires "Mojolicious"     => "8.00";
requires "JSON::Validator" => "3.09";

recommends "Text::Markdown" => "1.0.31";
recommends "YAML::XS"       => "0.75";

test_requires "Test::More" => "0.88";
