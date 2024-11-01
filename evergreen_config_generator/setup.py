# Copyright 2018-present MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import setuptools

setuptools.setup(
    name="evergreen_config_generator",
    version="0.0.1",
    author="A. Jesse Jiryu Davis",
    author_email="jesse@mongodb.com",
    description="Helpers for Python scripts that generate Evergreen configs",
    url="https://github.com/mongodb-labs/drivers-evergreen-tools",
    packages=["evergreen_config_generator"],
    install_requires=["PyYAML", "yamlordereddictloader"],
    classifiers=[
        "License :: OSI Approved :: Apache Software License",
    ],
)
