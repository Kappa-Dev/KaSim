from setuptools import setup

import distutils.cmd
import distutils.core
import subprocess
import setuptools.command.build_ext
import os.path

def should_build_agents():
    """
    Should we build agents? Currently this is decided based on
    checking for existence of a .ml file. Ideally, this should
    be made into a flag.
    """
    return os.path.isfile('core/agents/KaMoHa.ml')

class BuildAgentsCommand(distutils.cmd.Command):
    """Instruction to compile Kappa agents"""

    description = 'compile Kappa agents'
    user_options = [
    ]

    def initialize_options(self):
        ()

    def finalize_options(self):
        ()

    def run(self):
        if should_build_agents():
            try:
                subprocess.check_call(["make","all","agents"])
            except subprocess.CalledProcessError:
                print("Failed to compile Kappa agents. Installing Python " \
                      "wrapper only.")

class MyBuildExtCommand(setuptools.command.build_ext.build_ext):
    """Compile Kappa agent in addition of standard build"""

    def append_a_binary(self,bin_dir,name):
        file_in_src = os.path.realpath(os.path.join('bin',name))
        if os.path.isfile(file_in_src):
            distutils.file_util.copy_file(file_in_src, os.path.join(bin_dir,name))
            self.my_outputs.append(os.path.join(bin_dir, name))


    def run(self):
        self.my_outputs = []
        self.run_command('build_agents')
        bin_dir = os.path.join(self.build_lib, 'kappy/bin')
        distutils.dir_util.mkpath(bin_dir)
        self.append_a_binary(bin_dir,"KaSimAgent")
        self.append_a_binary(bin_dir,"KappaSwitchman")
        self.append_a_binary(bin_dir,"KaSaAgent")
        self.append_a_binary(bin_dir,"KaMoHa")
        setuptools.command.build_ext.build_ext.run(self)

    def get_outputs(self):
        outputs = setuptools.command.build_ext.build_ext.get_outputs(self)
        outputs.extend(self.my_outputs)
        return outputs

def readme():
    with open('README.md') as f:
        return f.read()

setup(name='kappy',
      license='LGPLv3',
      version='4.1.2',
      description='Wrapper to interact with the Kappa tool suite',
      long_description=readme(),
      long_description_content_type='text/markdown',
      url='https://github.com/Kappa-Dev/KappaTools.git',
      author='Kappa-Dev',
      author_email='kappa-dev@listes.sc.univ-paris-diderot.fr',
      classifiers=[
          'License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)',
          'Topic :: Scientific/Engineering :: Bio-Informatics'
      ],
      cmdclass={
          'build_agents': BuildAgentsCommand,
          'build_ext': MyBuildExtCommand,
      },
      install_requires=['requests', 'future', 'nose'],
      package_dir={'kappy':'kappy'},
      packages=['kappy'],
      zip_safe=False,
      # This distribution contains binaries not built with
      # distutils. So we must create a dummy Extension object so when
      # we create a binary file it knows to make it platform-specific.
      ext_modules=[distutils.core.Extension('kappy.dummy', sources = ['kappy/dummy.c'])],
)
