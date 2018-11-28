# evergreen_config_generator

Tools to generate a config.yml for Evergreen testing. Written for Python 2.6+.

We find that generating configuration from Python data structures is more
legible than Evergreen's matrix syntax or a handwritten file for the C and C++
Drivers' config files, and perhaps other for other projects.

This package is currently used by the C Driver, see [`generate-evergreen-config.py`]
(https://github.com/mongodb/mongo-c-driver/blob/master/build/generate-evergreen-config.py).
If you plan to write such an Evergreen-config-generator script in Python,
install this package with:

```
python -m pip install -e \
 git+https://github.com/mongodb-labs/drivers-evergreen-tools#subdirectory=evergreen_config_generator&egg=evergreen_config_generator
```

Write a script that creates an `OrderedDict` of Evergreen functions, tasks, and
variants, and uses the `generate(config, path)` function to write it to your
project's Evergreen YAML config file. Commit both the script and the YAML file
it outputs to git.
