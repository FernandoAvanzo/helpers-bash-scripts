# OpenAPI Scripts

1.3 - Download JAR
If you're looking for the latest stable version, you can grab it directly from Maven.org (Java 11 runtime at a minimum):

JAR location: https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/7.10.0/openapi-generator-cli-7.10.0.jar

For Mac/Linux users:
```bash
    wget https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/7.10.0/openapi-generator-cli-7.10.0.jar -O openapi-generator-cli.jar
```
One downside to manual jar downloads is that you don't keep up-to-date with the latest released version. We have a Bash launcher script at bin/utils/openapi-generator.cli.sh which resolves this issue.

To install the launcher script, copy the contents of the script to a location on your path and make the script executable.

An example of setting this up (NOTE: Always evaluate scripts curled from external systems before executing them).

```bash
    mkdir -p ~/bin/openapitools
    curl https://raw.githubusercontent.com/OpenAPITools/openapi-generator/master/bin/utils/openapi-generator-cli.sh > ./openapi-generator-cli.sh
    chmod u+x ~/bin/openapitools/openapi-generator-cli
    export PATH=$PATH:~/bin/openapitools/
```

Now, openapi-generator-cli is "installed". On invocation, it will query the GitHub repository for the most recently released version. If this matches the last downloaded jar, it will execute as normal. If a newer version is found, the script will download the latest release and execute it.

If you need to invoke an older version of the generator, you can define the variable OPENAPI_GENERATOR_VERSION either ad hoc or globally. You can export this variable if you'd like to persist a specific release version.

Examples:

# Execute latest released openapi-generator-cli
openapi-generator-cli version

# Execute version 4.1.0 for the current invocation, regardless of the latest released version
OPENAPI_GENERATOR_VERSION=4.1.0 openapi-generator-cli version

# Execute version 4.1.0-SNAPSHOT for the current invocation
OPENAPI_GENERATOR_VERSION=4.1.0-SNAPSHOT openapi-generator-cli version

# Execute version 4.0.2 for every invocation in the current shell session
export OPENAPI_GENERATOR_VERSION=4.0.2
openapi-generator-cli version # is 4.0.2
openapi-generator-cli version # is also 4.0.2

# To "install" a specific version, set the variable in .bashrc/.bash_profile
echo "export OPENAPI_GENERATOR_VERSION=4.0.2" >> ~/.bashrc
source ~/.bashrc
openapi-generator-cli version # is always 4.0.2, unless any of the above overrides are done ad hoc


### References
- [openapi-code-generator-cli-install](https://github.com/OpenAPITools/openapi-generator?tab=readme-ov-file#1---installation)