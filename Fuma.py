import os
import traceback
import re
import shutil
import threading
import time
from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime
from pathlib import Path
from shutil import move
from zipfile import ZIP_DEFLATED, ZipFile
from halo import Halo
import logging as pylog
import logging.handlers
import colorama
import yaml
from colorama import Fore, Style
from keyring import get_credential
from lxml import etree
from paramiko import SSHClient, AutoAddPolicy
from scp import SCPClient, SCPException
from yamlordereddictloader import Loader
import tarfile
import sys
import socket

current_date = datetime.now()
setup_file = Path
application_name = 'FUMA'
application_version = '2.4.121'
__shell_type__ = 'bash'
__archive_type__ = 'tar.gz'

ssh_spinner = Halo(text='Downloading', spinner='dots')


def ssh_progress(filename, size, sent):
    percent = (sent / float(size)) * 100
    ssh_spinner.text = f'[{percent:.2f}% ]: Downloading {Path(filename).name} | {sent:0,.2f} of {size:0,.2f} '


def archive_command(style: str, action: str, file_path=None, target=None) -> str:
    if action.lower() == 'c':
        if style.lower() == 'zip':
            return f"zip -rq {file_path}.{style} {target}"
        elif style.lower() in ('tar.gz', 'tgz', 'tar'):
            return f"tar -cf {file_path}.{style} {target}"
        else:
            return ''
    elif action.lower() == 'd':
        if style.lower() == 'zip':
            return f"unzip -q -o {file_path}.{style} -d {target}"
        elif style.lower() in ('tar.gz', 'tgz', 'tar'):
            return f"tar -xf {file_path}.{style} -C {target}"
        else:
            return ''


def get_login(service_name):
    _login = {}
    for _domain in ['DB', 'OS']:
        _name = f"{application_name}_{service_name}_{_domain}"
        _credential = get_credential(_name, None)
        _login[_domain] = dict(username=None, password=None)
        if _credential:
            _login[_domain]['username'] = _credential.username
            _login[_domain]['password'] = _credential.password
    return _login


class LoggingHandler:
    log_level = pylog.WARNING
    log = pylog.getLogger(f"{application_name}{application_version}")
    logpath = Path

    def __init__(self, *args, **kwargs):
        self.log = pylog.getLogger(self.__class__.__name__)
        self.set_level(kwargs['level'])
        self.logpath = Path(kwargs['file']).with_suffix('.log')
        # self.logpath.unlink(missing_ok=True)
        # print(f"{Fore.MAGENTA}Log file  : {self.logpath.__str__()} {Style.RESET_ALL}")
        handler = logging.handlers.WatchedFileHandler(self.logpath)
        formatter = pylog.Formatter(
            "[ %(asctime)s %(name)s %(threadName)s ] %(funcName)s  %(message)s")
        handler.setFormatter(formatter)

        self.log.addHandler(handler)

    def set_level(self, level):
        # print(f"{Fore.MAGENTA}Log level : {level} {Style.RESET_ALL}")
        self.log_level = pylog.DEBUG if level == 'debug' else pylog.INFO if level.startswith(
            'info') else pylog.WARNING if level.startswith('warn') else pylog.ERROR
        self.log.setLevel(level=self.log_level)

    def print_info(self, msg):
        return
        # print(f"{Fore.MAGENTA} [INFO {self.log.name} {self.log.level}] {msg} {Style.RESET_ALL}")
        # self.log.info(msg)


class OAF(LoggingHandler):
    jdev_home = Path(os.environ["JDEV_USER_HOME"]).joinpath("myclasses")
    token_regexp = re.compile(
        r"(?<={{)([\w.:<>]+)(?=}})", re.IGNORECASE | re.MULTILINE)
    template = None
    build_path = None
    config_path = None
    package = None
    current_date = datetime.now()
    yaml_file = None
    build_oaf = False

    max_backups = 10
    workspace = None
    outfile = None
    archive = None
    exclude = []
    include = []
    deployment_mode = 'full'

    def __init__(self, config, template, lock, log_level):
        # with lock:
        try:
            super().__init__(file=config, level=log_level)
            assert config
            assert template
            self.template = template


            if not isinstance(config, (dict, OrderedDict)):
                path = Path(config)
                if not (path.exists and path.is_file()):
                    raise AssertionError(
                        "{} is not a valid configuration file. ".format(path))
                self.config_path = path
                with open(path) as fh:
                    detail = yaml.load(fh, Loader=Loader)['config']
            else:
                detail = OrderedDict(config['config'])

            _setup = detail.get("setup", {})
            _key = _setup.get("deployment", {}).get("environment", _setup.get("environment"))
            _env = detail.get("environment", {}).get(_key)

            if not (detail.get('oaf') and _setup.get("deployment", {}).get("oaf")):
                self.build_oaf = detail.get('oaf') != None
                if not self.build_oaf:
                    return
            
            assert self.jdev_home.exists() and self.jdev_home.is_dir()
            assert self.template.exists() and self.template.is_file()
                
            self.build_oaf = True
            self.package = detail['oaf']['package'].format(**detail['oaf'])
            _wd = self.package.split('.')
            self.workspace = self.jdev_home.joinpath(*_wd)
            # print(self.workspace )

            for _path in detail['oaf'].get('include', []):
                self.include.extend(self.file_path(_path,self.workspace))

            for _path in detail['oaf'].get('exclude', []):
                self.exclude.extend(self.file_path(_path,self.workspace))


            # -------------
            self.shell_type = _env.get('shell', __shell_type__)
            self.archive_type = _env.get('archive', __archive_type__)
            # --------------

            _sh = "import_{file}.sh".format(file="_".join(_wd[-2:]))
            _zip = "{file}.{ext}".format(file="_".join(_wd[-1:]), ext=self.archive_type)

            _wd[-1] = _sh
            self.outfile = self.jdev_home.joinpath(*_wd)
            _wd[-1] = _zip
            self.archive = self.jdev_home.joinpath(*_wd)
            files = self.xml_mds()

            _style = 'thin' if self.exclude or self.include else 'full'
            _structure = self.zip_project()

            token = {
                'version' : str(application_version),
                'project': Path(*(self.package.split('.')[:-1])).as_posix(),
                'solution': self.package.split('.')[-1],
                'timestamp': datetime.strftime(datetime.now(), "%d-%m-%Y %H:%M:%S"),
                'files': files,
                'struct_folders': _structure['folder'],
                'struct_files': _structure['file'],
                'deploy_style': _style,
                'archive_file': self.archive.name,
                'archive_type': 'tar' if 'tar' in self.archive_type.split('.')  else self.archive_type 
            }

            # self.log.info(f"environment : {_key}, ({_env})")
            self.shell_file(token)
            self.build(_setup, _env)

            # if _setup:
            #     if _env and _setup.get("environment") in _env :
            #         _key = _setup.get("deployment", {}).get("environment", _setup["environment"])
            #         _env = _env[_key]
            #         self.log.info(f"environment : {_key}, ({_env})")
            #     else:
            #         _env = None


        except Exception as oe:
            traceback.print_exc()
            print("{color}{msg}{rst}".format(
                color=Fore.RED, msg=oe, rst=Style.RESET_ALL))
            
    def file_path(self, input_path, root_dir):
        # Convert the input to a Path object to handle OS-specific path separators
        root_dir = Path(root_dir)

        # Normalize package-style notation (e.g., employee.schema.server) to path-style
        if "." in input_path and not "/" in input_path and not "\\" in input_path:
            normalized_path = Path(input_path.replace(".", "/"))
        else:
            normalized_path = Path(input_path)

        # Handle wildcards if present
        if "*" in str(normalized_path):
            # Use glob to handle the wildcard patternbuild_oaf
            matched_files = list(root_dir.glob(str(normalized_path)))
        else:
            # Treat it as a direct path or package path without wildcards
            full_path = root_dir / normalized_path
            if full_path.exists():
                matched_files = [full_path]
            else:
                matched_files = []

        # Print matched files or return the first match
        if matched_files:
            return matched_files
        else:
            return []

    def deploy(self, env, opt):
        if not self.build_oaf:
            return
        
        _login = get_login(env['name'])

        host = env["host"]

        os_user = _login['OS']['username']
        db_user = _login['DB']['username']
        os_pwd = _login['OS']['password']
        db_pwd = _login['DB']['password']
        os_home = env['home'].format(**globals())

        if not os_pwd:
            raise AssertionError(
                "OS login details for '{host}' could not be loaded.".format(**env))
        if not db_pwd:
            raise AssertionError(
                f"Database login details for '{db_user}@{env['name']}' could not be loaded.")

        env['pass'] = db_pwd
        env['script'] = self.outfile.name
        env['bounce'] = 'bounce' if opt.get("bounce", False) else ''

        d = dict(project=self.package,
                 env=env["host"], color=Fore.CYAN, reset=Style.RESET_ALL)
        print("{color}Attempting to deploy '{project}' to {env} {reset}".format(**d))

        try:
            con = SSHClient()
            con.set_missing_host_key_policy(AutoAddPolicy())
            con.connect(host, username=os_user, password=os_pwd)
            con.exec_command(f"mkdir -p {os_home}; ")

            with SCPClient(con.get_transport()) as scp:
                scp.put(self.archive, os_home)
                scp.put(self.outfile, os_home)

            cmd = [
                ". {file} run",
                f"cd {os_home}",
                "http_proxy='http://localhost'",
                "pass='{pass}'",
                "export pass",
                "affirm='Y'",
                "export affirm",
                f"{self.shell_type} {env['script']} {self.deployment_mode} {env['bounce']}"
            ]

            cmd = ";\n".join(cmd).format(**env)
            self.log.info(cmd)

            stdin, stdout, stderr = con.exec_command(cmd)
            print(stdout.read().decode())

            con.close()
        except Exception as de:
            print("Deployment Cancelled. Unable to establish connection.", de)

    def build(self, setup, env):
        _opt = setup.get("deployment")
        if _opt and "oaf" in _opt:
            if _opt["oaf"]:
                assert env
                self.deploy(env, _opt)
            else:
                assert setup.get("build")
                bp = Path(setup["build"].format(**globals()))
                if bp.is_absolute():
                    self.build_path = bp
                else:
                    assert self.config_path
                    self.build_path = Path(self.config_path).parent.joinpath(
                        bp, "oaf").absolute()
                self.build_path.mkdir(parents=True, exist_ok=True)
                d = dict(path=self.build_path.absolute(),
                         color=Fore.GREEN, reset=Style.RESET_ALL)
                print("{color}OAF Resources path : {path}{reset}".format(**d))
                move(self.archive, self.build_path.joinpath(self.archive.name))
                move(self.outfile, self.build_path.joinpath(self.outfile.name))

    def xml_mds(self):
        files = []
        for x in self.workspace.rglob('**/*.xml'):
            if self.include and not any([x.is_relative_to(_path) for _path in self.include]):
                continue
            if self.exclude and any([x.is_relative_to(_path) for _path in self.exclude]):
                continue

            tree = etree.parse(x.open())
            root = tree.getroot()
            if not ('ui' in root.nsmap.keys()):
                continue
            
            self.log.info(f'adding : {x}')
            files.append(x.relative_to(self.jdev_home).as_posix())

        files = ["\t'{}'".format(file) for file in files]
        return "\n".join(files)

    def zip_project(self):
        if self.archive.exists():
            stats = {}
            for _seq, _archive in enumerate(self.archive.parent.glob(self.archive.stem + '*' + self.archive.suffix)):
                stats.setdefault(_archive.stat().st_mtime_ns, _archive)

            # print("backups ", len(stats))
            backup = None
            if self.max_backups >= len(stats):
                for seq in range(self.max_backups):
                    backup = "{file}{seq:02d}{ext}".format(file=self.archive.stem, seq=seq + 1,
                                                           ext=self.archive.suffix)
                    backup = self.archive.parent.joinpath(backup)

                    if backup.exists():
                        continue
                    break

            else:
                _keys = sorted(stats, reverse=False)
                backup = stats[_keys[0]]

            backup.unlink(missing_ok=True)
            self.archive.rename(backup)

        _fs = dict(folder=list(), file=list())
        _items = list()

        self.deployment_mode = 'partial' if self.exclude  or self.include else 'full'

        for item in self.workspace.rglob("*"):
            
            if self.include and not any([item.match(_path) or item.is_relative_to(_path) for _path in self.include]):
                continue

            if self.exclude and any([item.match(_path) or item.is_relative_to(_path) for _path in self.include]):
                continue

            self.log.info(f'Adding : {item}')

            if item.is_file():
                _fs['folder'].append(
                    item.parent.relative_to(self.jdev_home).as_posix())
                _fs['file'].append(item.relative_to(
                    self.jdev_home).as_posix())
            else:
                _fs['folder'].append(
                    item.parent.relative_to(self.jdev_home).as_posix())

            _items.append(dict(o=item, p=item.relative_to(self.workspace.parent)))

            # zf.write(item, item.relative_to(self.workspace.parent))

        _fs['folder'] = '\n'.join(["\t'{0}'".format(i) for i in list(dict.fromkeys(_fs['folder']))])
        _fs['file'] = '\n'.join(["\t'{0}'".format(i) for i in list(dict.fromkeys(_fs['file']))])

        if _items:
            self.log.info(f"{self.archive_type=}")
            self.log.info(f"{self.archive=}")

            if self.archive_type == 'zip':
                with ZipFile(self.archive, 'w', ZIP_DEFLATED) as zf:
                    for _item in _items:
                        zf.write(_item['o'], _item['p'])
            elif 'tar' in self.archive_type.split('.'):
                with tarfile.open(self.archive, 'w:gz', format=tarfile.GNU_FORMAT) as zf:
                    for _item in _items:
                        zf.add(_item['o'], arcname=_item['p'])
        return _fs

    def shell_file(self, token):
        with open(self.template) as rh:
            # print("generating deployment script ", self.outfile)
            with open(self.outfile, "w", newline="\n") as wh:
                shell = yaml.load(rh, Loader=Loader)['shell']
                wh.write("\n".join(shell['license']).format(**token))
                for seq, block in enumerate(shell['oaf']):
                    if self.token_regexp.findall(block):
                        block = block.format(**token)
                    wh.write(block)


class AOL(LoggingHandler):
    template = Path
    out_dir = Path
    sql_out_dir = Path
    out_file = Path
    shell_directory = Path(os.environ["FUMA_DIRECTORY"], "shell")
    export_script = shell_directory.joinpath('ldt_export.sh')
    load_process = 'import'
    cleanup = True
    remote_download = True
    config_path = Path
    current_date = datetime.now()
    max_download_reries = 3

    application = None

    def __init__(self, config, template, lock, log_level):
        # with lock:
        super().__init__(file=config, level=log_level)
        assert config
        assert template

        self.template = template
        assert self.template.exists() and self.template.is_file()

        path = Path(config)
        if not (path.exists and path.is_file()):
            raise AssertionError(
                "{} is not a valid configuration file. ".format(path))

        self.config_path = path
        self.file_name = f"{path.stem}_{current_date:%Y%m%d}"

        with open(path) as fh:
            detail = yaml.load(fh, Loader=Loader)['config']

        self.application = detail.get("application", "XXSFC")

        _setup = detail.get("setup", {})
        _deploy = False
        env = None
        _target = None

        if _setup.get('file_name'):
            self.file_name = _setup.get('file_name', '').format(**globals())

        if _setup and 'build' in _setup:
            _target = detail['environment'].get(_setup['deployment'].get("environment", 'local'), {})
            _deploy = _setup['deployment'].get("aol", False)
            self.cleanup = _setup['deployment'].get("cleanup", True)
            self.log.debug(f"AOL Clean up temporary files : {self.cleanup}")
            _deployment_source = _setup['deployment'].get("source", "remote").lower()
            self.log.debug(f"AOL Deployment Mode : {_deployment_source}")
            self.remote_download = _deployment_source != 'local'
            if not _deploy:
                return

            if self.remote_download:
                try:
                    env = detail['environment'][detail['setup']['environment']]
                    os_home = env['home'].format(**globals())

                    # -------------
                    self.shell_type = env.get('shell', __shell_type__)
                    self.archive_type = env.get('archive', __archive_type__)
                    # --------------

                    self.log.debug(f'''
                            AOL download details :
                                name            : {env['name']}
                                host            : {env['host']}
                                context         : {env['file']}
                                directory       : {os_home}
                                shell type      : {self.shell_type}
                                archive type    : {self.archive_type}
                        ''')
                except Exception:
                    raise AssertionError(
                        "Invalid deployment profile: Environment must be specified.")
            else:
                env = {}

            _build = Path(_setup['build'].format(**globals())).joinpath("aol")
            if _build.is_absolute():
                self.out_dir = _build
            else:
                self.out_dir = path.parent.joinpath(_build)
        else:
            self.out_dir = Path.home().joinpath("Desktop", "aol")

        self.sql_out_dir = self.out_dir.parent.joinpath("sql")
        self.out_dir.mkdir(parents=True, exist_ok=True)
        detail.setdefault("schema", "01")
        detail.setdefault("prefix", "02")
        self.out_file = self.out_dir.joinpath(
            "aol.{schema}.{prefix}.sh".format(**detail))
        self.log.debug(f"AOL Output directory   : {self.out_dir}")
        self.log.debug(f"SQL Output directory   : {self.sql_out_dir}")
        self.log.debug(f"Temporary shell script : {self.out_file}")
        self.log.debug(f"AOL Deployment Enabled : {_deploy}")
        # print(self.out_file)
        if not _deploy:
            return
        cmd = self.build(detail.get("aol"))
        self.log.debug(f"Commands :\n{cmd}")
        # print(cmd)
        # return
        deps = self.shell_file(cmd)
        if env and self.out_file.exists():
            _zip_path = self.deploy(env, deps)
            self.log.info(f"zip path : {_zip_path}; Target : {_target}")
            self.remote_deploy(_target, Path(_zip_path).name)

    def shell_file(self, commands):
        token = {'timestamp': datetime.strftime(
            datetime.now(), "%d-%m-%Y %H:%M:%S"), 'version': str(application_version)} 
        # if self.out_file.exists():
        self.out_file.unlink(missing_ok=True)
        dependency = {}
        if not commands:
            return
        with open(self.template) as rh:
            with open(self.out_file, "w", newline="\n") as wh:
                shell = yaml.load(rh, Loader=Loader)['shell']
                try:
                    dependency = shell.get("dependency", {}).get(
                        self.load_process, {})
                except Exception as de:
                    print(de)

                wh.write("\n".join(shell['license']).format(**token))
                for seq, block in enumerate(shell['aol']):
                    wh.write(block)
                wh.write(commands)
        return dependency.get("aol", {})
        # d = dict(path=self.out_dir.absolute(), color=Fore.GREEN, reset=Style.RESET_ALL)
        # print("{color}AOL Resources path : {path}{reset}".format(**d))

    def build(self, objects):
        if not objects:
            return
        cmds = []
        prcs = []
        _cmd = self.shell_type + " {{file}} -n {n} -o {o} -a {a}{e} {extra} &"
        _prc = 'fuma_pc_{seq:02d}'
        _prcx = 'fuma_pid'
        _prcf = []
        prcn = 0

        for obj in objects.get("general", []):
            d = dict(n='"{}"'.format(obj['object']), e="", o=" -o ".join(obj['type']),
                     a=obj.get("application", self.application), extra="")
            cmds.append(_cmd.format(**d))
            prcn += 1
            proc_name = _prc.format(seq=prcn)
            # cmds.append(proc_name + "=${{!}};")
            cmds.append(f"{_prcx}+=($!)")
            # prcs.append(f"wait ${proc_name};")

        for item in objects.get("special", []):

            for key, values in item.items():
                _ki = 0
                for _value in values.get("object", []):
                    _ki += 1
                    _n = []
                    _o = [key]
                    _e = []
                    d = dict(a=values.get("application",
                                          self.application), extra="")
                    if isinstance(_value, str):
                        _n.append(_value)
                        if key.lower() in ('package'):
                            d['extra'] = '{0} -r {1} -u {2}'.format(
                                d['extra'], _ki, values.get("schema", 'apps'))
                        if key.lower() in ('path'):
                            d['extra'] = '{0} -r {1}'.format(d['extra'], _ki)
                        if key.lower() in ('personalization'):
                            d['extra'] = f" -f {values.get('type', 'oaf').lower()}"
                    else:
                        for _key in _value:
                            _n.append(_key.replace("'", "'\''"))
                            if key.lower() == 'program' and _value[_key]:
                                _t = _value[_key]['type']
                                if _t:
                                    _e.append(" -f {}".format(_t))
                                    if _t.upper().strip() == 'XML':
                                        _o.append('template')

                                for opt in ['layout', 'bursting']:
                                    if _value[_key].get(opt):
                                        _o.append(opt)
                                        if opt == 'layout':
                                            _o.append('data_definition')
                            if key.lower() == 'dff' and _value[_key]:
                                _vl = _value[_key].get('flexfield')
                                if not _vl:
                                    continue
                                d['extra'] = '{0} -c "{1}"'.format(
                                    d['extra'], _vl)
                                if _value[_key].get('application'):
                                    d['a'] = _value[_key].get('application')

                            if key.lower() == 'package':
                                print(_value[_key])

                    d['n'] = " -n ".join([f"'{n}'" for n in _n])
                    d['o'] = " -o ".join(_o)
                    d['e'] = " ".join(_e)
                    cmds.append(_cmd.format(**d))
                    prcn += 1
                    proc_name = _prc.format(seq=prcn)
                    # cmds.append(proc_name+"=${{!}};")
                    cmds.append(f"{_prcx}+=($!)")
                    # prcs.append(f"wait ${proc_name};")

        _prcf.append(f'for fbpid in "${{{_prcx}[@]}}"; do')
        _prcf.append(f'wait ${{fbpid}};')
        _prcf.append('done')

        return '\n'.join(["\n".join(cmds).format(file=self.export_script.name), "\n".join(prcs), "\n".join(_prcf)])

    def remote_deploy(self, env, file):
        if not env:
            return

        _login = get_login(env['name'])

        host = env["host"]

        os_user = _login['OS']['username']
        db_user = _login['DB']['username']
        os_pwd = _login['OS']['password']
        db_pwd = _login['DB']['password']

        sql = None
        home = Path(env["home"].format(**globals())).joinpath("aol")
        dir_size = sum(z.stat().st_size for z in self.sql_out_dir.rglob('*'))
        self.log.info(
            f"SQL Dependencies '{self.sql_out_dir}' exists '{self.sql_out_dir.exists()}'" +
            f" ({dir_size:,d})")

        if self.sql_out_dir.exists() and dir_size > 0:
            sql = home.joinpath("sql")
            sql = sql.as_posix()

        home = home.as_posix()
        # ldt_zip = ldt_dir.parent.joinpath(f"{ldt}.zip").as_posix()

        self.log.info(f'Remote Deploy : Working Directory {home}')
        self.log.info(f'Remote Deploy : Archive File {file}')
        # self.log.info(
        #     f"SQL Directory : {self.sql_out_dir} exists : {self.sql_out_dir.exists()}
        #     + Stats : {self.sql_out_dir.stat().st_size}")
        # return

        if not os_pwd:
            raise AssertionError(
                "OS login details for '{host}' could not be loaded.".format(**env))
        if not db_pwd:
            raise AssertionError(
                "Database login details for 'apps@{name}' could not be loaded.".format(**env))
        # cmd = "mkdir -p {path};".format(path=sql if sql else home)
        cmd = [f"rm -rf {home}",
               f"mkdir -p {home}",
               f"mkdir -p {sql}" if sql else None,
               ]
        # if sql:
        #     cmd = [f"mkdir -p {sql};"]
        # else :
        #     cmd = [f"mkdir -p {home};"]

        d = dict(env=env["host"], path=self.out_dir.absolute(),
                 color=Fore.CYAN, reset=Style.RESET_ALL)
        print("{color}Attempting to upload AOL to {env}{reset}".format(**d))
        self.log.info("Returning execution")
        try:
            con = SSHClient()
            con.set_missing_host_key_policy(AutoAddPolicy())
            con.connect(host, username=os_user, password=os_pwd)
            cmd = [i.strip() for i in cmd if i and i.strip()]
            cmd = ";\n".join(cmd)
            self.log.info(f"Executing : {cmd}")
            con.exec_command(cmd)

            with SCPClient(con.get_transport()) as scp:
                for _f in self.out_dir.rglob("*"):
                    self.log.info(f"Uploading {_f} to {home}")
                    scp.put(_f.__str__(), home)
                if sql:
                    for _i in self.sql_out_dir.rglob("*"):
                        self.log.info(f"Uploading {_i} to {sql}")
                        scp.put(_i.__str__(), sql)

                # scp.put(self.out_file, home)

            cmd = [
                f"source {env['file']} run",
                f"cd {home}",
                "http_proxy='http://localhost'",
                f"export DK_AU_PASS='{db_pwd}'",
                f"export DK_AU_ENV='{env['name']}'",
                "export affirm='Y'",
                f"{self.shell_type} fnd_import.sh -s {sql}" if sql else None,
                f"{self.shell_type} fnd_import.sh -s {file}",
            ]
            cmd = [i.strip() for i in cmd if i and i.strip()]
            cmd = ";\n".join(cmd)
            self.log.info(cmd)

            stdin, stdout, stderr = con.exec_command(cmd)
            print(stdout.read().decode())
            con.close()

        except Exception as de:
            print("Deployment Cancelled. Unable to establish connection.", de)

    def deploy(self, env, deps):
        """Deploys files to a remote server and handles dependencies."""
        try:
            # Fetch login credentials
            _login = get_login(env['name'])
            host = env["host"]
            os_user = _login['OS']['username']
            db_user = _login['DB']['username']
            os_pwd = _login['OS']['password']
            db_pwd = _login['DB']['password']

            # Construct paths
            home = Path(env["home"].format(**globals())).joinpath("aol")
            ldt_dir = home.joinpath("ldt")
            ldt = self.file_name
            home = home.as_posix()
            _zip_name = f"{ldt}.{self.archive_type}"
            ldt_zip = ldt_dir.parent.joinpath(_zip_name).as_posix()

            self.log.info(f"Generating archive: {ldt_zip}")

            # Validate credentials
            if self.remote_download:
                if not os_pwd:
                    raise ValueError(f"OS login details for '{host}' could not be loaded.")
                if not db_pwd:
                    raise ValueError(f"Database login details for '{db_user}@{env['name']}' could not be loaded.")

            cmd_init = f"mkdir -p {home}"

            # Log and display attempt message
            d = dict(env=env["host"], path=self.out_dir.absolute(), color=Fore.CYAN, reset=Style.RESET_ALL)
            print(f"{Fore.CYAN}Attempting to download AOL from {host}{Style.RESET_ALL}")

            if self.remote_download:
                with SSHClient() as con:
                    con.set_missing_host_key_policy(AutoAddPolicy())
                    con.connect(host, username=os_user, password=os_pwd, timeout=60)

                    # Execute initialization command
                    self.log.info(f"Executing: {cmd_init}")
                    _, stdout, stderr = con.exec_command(cmd_init)
                    self.log.info(stdout.read().decode().strip())
                    # print(stdout.read().decode().strip())
                    error_msg = stderr.read().decode().strip()
                    if error_msg:
                        self.log.error(error_msg)

                    # Upload required files
                    with SCPClient(con.get_transport()) as scp:
                        scp.put(self.export_script, home)
                        scp.put(self.out_file, home)

                    # Construct deployment commands
                    cmd_deploy = [
                        f". {env['file']} run",
                        f"cd {home}",
                        "http_proxy='http://localhost'",
                        f"export pass='{db_pwd}'",
                        f"export out_dir='{ldt}'",
                        f"rm -rf {_zip_name}",
                        f"{self.shell_type} {self.out_file.name}",
                        f"cd {ldt}",
                        archive_command(self.archive_type, 'c', Path(f'../{ldt}').as_posix(), '.'),
                        "cd ..",
                        f"du -sh {_zip_name}",
                        f"rm -rf {ldt}",
                        f"rm -rf {home}/*.sh"
                    ]
                    cmd_deploy = ";\n".join(filter(None, cmd_deploy))  # Remove empty commands
                    self.log.info(f"Executing Deployment: {cmd_deploy}")

                    _, stdout, stderr = con.exec_command(cmd_deploy)
                    output = stdout.read().decode().strip()
                    error_output = stderr.read().decode().strip()
                    if output:
                        self.log.info(output)
                        print(output)
                    if error_output:
                        self.log.error(error_output)
                        print(error_output)

                    # Attempt file download with retries
                    _target = self.out_dir.joinpath(_zip_name).absolute().__str__()
                    self.log.info(f"FTP: {ldt_zip} --> {_target}")

                    for retry in range(self.max_download_reries):
                        try:
                            with SCPClient(con.get_transport(), progress=ssh_progress, socket_timeout=300) as scp:
                                scp.get(ldt_zip, _target)
                                ssh_spinner.succeed(f"Download Successful. File saved as {_target}")
                                break
                        except (SCPException, socket.timeout) as e:
                            retry_delay = 10
                            if retry == self.max_download_reries - 1:
                                ssh_spinner.fail(f"Download failed after {self.max_download_reries} attempts.")
                                self.log.error(f"Download failed: {e}")
                            else:
                                ssh_spinner.warn(f"Error: {e}. Retrying in {retry_delay} seconds... ({retry + 1}/{self.max_download_reries})")
                                time.sleep(retry_delay)
                        except Exception as shex:
                            ssh_spinner.fail("Download failed")
                            self.log.error(f"Unexpected error during download: {shex}")
                            break  # Exit retry loop on unexpected error

                        ssh_spinner.stop_and_persist()

                    # Cleanup if enabled
                    if self.cleanup:
                        self.out_file.unlink(missing_ok=True)
                    else:
                        print(f"AOL outfile: {self.out_file}")

                    print(f"{Fore.CYAN}AOL Resources path: {self.out_dir.absolute()}{Style.RESET_ALL}")

            # Process dependencies
            for obj in deps:
                for file, meta in obj.items():
                    _description = meta.get('description', 'Dependencies')
                    print(f"{Fore.CYAN}Configuring {_description}...{Style.RESET_ALL}")
                    _f = self.shell_directory.joinpath(file)
                    if _f.exists():
                        for target in meta.get('target', []):
                            _t = self.out_dir.absolute().joinpath(target)
                            shutil.copy(str(_f), str(_t))

            return ldt_zip

        except ValueError as ve:
            self.log.error(f"Validation Error: {ve}")
            print(f"{Fore.RED}Validation Error: {ve}{Style.RESET_ALL}")

        except SCPException as scpe:
            self.log.error(f"SCP Transfer Error: {scpe}")
            print(f"{Fore.RED}SCP Transfer Error: {scpe}{Style.RESET_ALL}")

        except socket.timeout:
            self.log.error("Connection Timeout: Unable to reach remote host.")
            print(f"{Fore.RED}Connection Timeout: Unable to reach remote host.{Style.RESET_ALL}")

        except Exception as de:
            self.log.error(f"Deployment Failed: {de}")
            print(f"{Fore.RED}Deployment Cancelled. {de}{Style.RESET_ALL}")
    
    # def deploy(self, env, deps):

    #     _login = get_login(env['name'])

    #     host = env["host"]

    #     os_user = _login['OS']['username']
    #     db_user = _login['DB']['username']
    #     os_pwd = _login['OS']['password']
    #     db_pwd = _login['DB']['password']

    #     home = Path(env["home"].format(**globals())).joinpath("aol")
    #     ldt_dir = home.joinpath("ldt")
    #     ldt = self.file_name
    #     home = home.as_posix()
    #     _zip_name = f"{ldt}.{self.archive_type}"
    #     ldt_zip = ldt_dir.parent.joinpath(_zip_name).as_posix()

    #     self.log.info(f"generating archive : {ldt_zip}")

    #     if self.remote_download and not os_pwd:
    #         raise AssertionError(
    #             "OS login details for '{host}' could not be loaded.".format(**env))
    #     if self.remote_download and not db_pwd:
    #         raise AssertionError(
    #             f"Database login details for '{db_user}@{env['name']}' could not be loaded.")

    #     cmd = f"mkdir -p {home};"

    #     d = dict(env=env["host"], path=self.out_dir.absolute(),
    #              color=Fore.CYAN, reset=Style.RESET_ALL)
    #     print("{color}Attempting to download AOL from {env}{reset}".format(**d))

    #     try:
    #         if self.remote_download:
    #             con = SSHClient()
    #             con.set_missing_host_key_policy(AutoAddPolicy())
    #             con.connect(host, username=os_user, password=os_pwd, timeout=60)
    #             con.exec_command(cmd)

    #             with SCPClient(con.get_transport()) as scp:
    #                 scp.put(self.export_script, home)
    #                 scp.put(self.out_file, home)

    #             cmd = [
    #                 f". {env['file']} run",
    #                 f"cd {home}",
    #                 "http_proxy='http://localhost'",
    #                 f"export pass='{db_pwd}'",
    #                 f"export out_dir='{ldt}'",
    #                 f"rm -rf {_zip_name}",
    #                 # f"sed -i 's/\\r$//' {self.out_file.name}",
    #                 # f'tr -d "\\r" < {self.out_file.name} > {self.out_file.name}',
    #                 f"{self.shell_type} {self.out_file.name}",
    #                 f"cd {ldt}",
    #                 archive_command(self.archive_type, 'c', Path(f'../{ldt}').as_posix(), '.'),
    #                 "cd ..",
    #                 # "wait",
    #                 f"du -sh {_zip_name}",
    #                 f"rm -rf {ldt}",
    #                 f"rm -rf {home}/*.sh"
    #             ]

    #             cmd = ";\n".join(cmd).format(script=self.out_file.name, file=env['file'])
    #             self.log.info(cmd)

    #             stdin, stdout, stderr = con.exec_command(cmd)
    #             print(stdout.read().decode())
    #             # self.log.info(stderr.read().decode())
    #             _target = self.out_dir.joinpath(_zip_name).absolute().__str__()
    #             self.log.info(f"FTP :: {ldt_zip} --> {_target}")

    #             for retry in range(self.max_download_reries):
    #                 ssh_spinner.start()
    #                 retry_delay = 10
    #                 try:
    #                     with SCPClient(con.get_transport(), progress=ssh_progress, socket_timeout=300) as scp:
    #                         scp.get(ldt_zip, _target)
    #                         ssh_spinner.succeed(f"Download Successful. File saved as {_target}")
    #                         break
    #                 except (SCPException, socket.timeout) as e:
    #                     # print(f"Error: {e}. Retrying in {retry_delay} seconds...")
    #                     if retry == self.max_download_reries:
    #                         ssh_spinner.fail(f"Download failed after {self.max_download_reries} attempts.")
    #                     else:
    #                         ssh_spinner.warn(
    #                             f"Error occurred : {shex}. Retrying in {retry_delay} seconds... {retry + 1} of {self.max_download_reries} attempts")
    #                         time.sleep(retry_delay)
    #                 except Exception as shex:
    #                     ssh_spinner.fail(f"Download failed")
                       
    #                 ssh_spinner.stop_and_persist()

    #             if self.cleanup:
    #                 # print(f"Deleting outfile : {self.out_file}")
    #                 self.out_file.unlink(missing_ok=True)
    #             else:
    #                 print(f"AOL outfile : {self.out_file}")

    #             con.close()

    #             print("{color}AOL Resources path : {path}{reset}".format(**d))

    #         for obj in deps:
    #             for file in obj:
    #                 # print(file, obj[file])
    #                 _description = obj[file].get('description', 'Depencies')
    #                 _description = f'Configuring {_description}'
    #                 print(f"{Fore.CYAN}{_description} ...{Style.RESET_ALL}")
    #                 _f = self.shell_directory.joinpath(file)
    #                 if _f.exists():
    #                     for t in obj[file].get('target', []):
    #                         _t = self.out_dir.absolute().joinpath(t)
    #                         shutil.copy(_f.__str__(), _t.__str__())
    #         return ldt_zip

    #     except Exception as de:
    #         print("Deployment Cancelled. Unable to establish connection.", de)


class SQL(LoggingHandler):
    template = Path
    out_dir = Path
    ddl_sql = Path
    dml_sql = Path
    config_path = Path
    current_date = datetime.now()

    types_config = Path(os.environ["FUMA_DIRECTORY"], r'_setup\_datatype.yml')
    token_regex = re.compile(
        r"{([\w]+)(?::(.(?!}))*.)?}", re.IGNORECASE | re.MULTILINE)
    db_template = OrderedDict

    def __init__(self, config, template, lock, log_level):
        # with lock:
        super().__init__(file=config, level=log_level)
        try:
            assert config
            assert template
            assert self.types_config.exists() and self.types_config.is_file()

            self.template = template
            _config_file = Path

            assert self.template.exists() and self.template.is_file()
            with open(self.template) as fh:
                self.db_template = yaml.load(fh, Loader=Loader)['database']

            if not isinstance(config, dict):
                path = Path(config)
                if not (path.exists and path.is_file()):
                    raise AssertionError(
                        "{} is not a valid configuration file. ".format(path))
                _config_file = path
                self.config_path = path
                with open(path) as fh:
                    detail = yaml.load(fh, Loader=Loader)
            else:
                detail = OrderedDict(config)

            if not detail['config'].get('schema') or not detail['config']['setup']['deployment'].get('sql'):
                return

            ddl_sql = "01.ddl.{schema}.{prefix}.sql".format(**detail['config'])
            dml_sql = "02.dml.{schema}.{prefix}.sql".format(**detail['config'])
            _setup = detail['config'].get('setup', {})

            # print(ddl_sql)

            if _setup and 'build' in _setup:
                _build = Path(_setup['build'].format(
                    **globals())).joinpath("sql")
                if _build.is_absolute():
                    self.out_dir = _build
                else:
                    assert _config_file
                    self.out_dir = _config_file.parent.joinpath(_build)
            else:
                self.out_dir = Path.home().joinpath("Desktop", "sql")

            self.out_dir.mkdir(parents=True, exist_ok=True)
            self.ddl_sql = self.out_dir.joinpath(ddl_sql)
            self.dml_sql = self.out_dir.joinpath(dml_sql)

            self.log.debug(f"DDL File : {self.ddl_sql}")
            self.log.debug(f"DML File : {self.dml_sql}")

            # print("dml_sql : ", self.dml_sql)

            self.ddl(detail['config']['schema'], detail['config']['prefix'], detail.get('tables'),
                     _setup.get('table', {}), detail['config'].get('build', {}).get('table', {}))
        except Exception as se:
            print("{color}{msg}{rst}".format(
                color=Fore.RED, msg=se, rst=Style.RESET_ALL))

    def ddl(self, schema, prefix, objects, setup, build={}):
        if not objects:
            return
        assert isinstance(objects, (OrderedDict, dict))

        with open(self.types_config) as fh:
            config_selector = 'oracle'
            self.log.debug(f"Loading Configuration : {config_selector}")

            config = yaml.load(fh, Loader=Loader)[config_selector]
            data_type = config['types']
            who_column = config['who']
            extra_column = config['extra']
            validation = config['validation']

        extra_columns = {}
        file_tokens = {
            'sequence': [],
            'table': [],
            'primary key': [],
            'foreign key': [],
            'index': []
        }

        for _col in extra_column:
            # print(_col)
            if 'count' in extra_column[_col]:
                _ec_override = setup.get(_col, {})

                _ec_override_flag = False
                _len = extra_column[_col]['count']
                if _ec_override and isinstance(_ec_override, dict):
                    _len = _ec_override.get('count', _len)
                    _ec_override_flag = True
                    for v in extra_column[_col]:
                        _ec_override.setdefault(v, extra_column[_col][v])
                elif str(_ec_override).isnumeric():
                    _len = _ec_override

                # print(_ec_override)
                # _len = setup.get(_col, extra_column[_col]['count'])
                for i in range(_len):
                    _key = "{0}{1}".format(_col, i + 1)
                    if _ec_override_flag:
                        extra_columns[_key] = _ec_override
                    else:
                        extra_columns[_key] = extra_column[_col]

                    extra_columns[_key].pop('count', None)
            else:
                extra_columns[_col] = extra_column[_col]

        _include = set([i.lower() for i in build.get('include', [])])
        _exclude = set([i.lower() for i in build.get('exclude', [])])
        _exclude.difference_update(_include)

        if _include:
            self.log.debug('Tables to include : ' + ','.join(list(_include)))
        if _exclude:
            self.log.debug('Tables to exclude : ' + ','.join(list(_exclude)))

        for table in objects:
            if (_include and table not in _include) or (_exclude and table in _exclude):
                # self.log.debug(f"Exluding table {table} from build")
                continue

            timestamp = '{:%d-%m-%Y %H:%M:%S}'.format(datetime.now())
            tokens = {
                'schema': schema,
                'prefix': prefix,
                'table': table,
                'name': "{0}_{1}".format(prefix, table),
                'comments': objects[table].get('description', 'Generated at {}'.format(timestamp)).strip()
            }

            # print(table)
            self.log.debug(
                f"Applying validations on Table '{tokens['name']}': REGEXP '{validation['name']}'")
            id_regexp = re.compile(
                validation['name'], re.IGNORECASE | re.MULTILINE)

            if not id_regexp.fullmatch(tokens['name']):
                raise AssertionError(
                    "invalid table name '{}'.".format(tokens['name']))

            _table = "{schema}.{prefix}_{table}".format(**tokens)
            tokens['object'] = _table

            columns = objects[table].get('columns', {})
            if not columns:
                continue

            _index = objects[table].get('index', None)
            if _index:
                for it in _index:
                    for i, ic in enumerate(_index[it]):
                        ik = "{} index".format(
                            '' if it == 'normal' else it).strip()
                        nm = "{0}_{1}{2}".format(tokens['name'], ik[0], i + 1)

                        self.log.debug(f"Validating '{it}' Index '{nm}'")

                        if not id_regexp.fullmatch(nm):
                            raise AssertionError(
                                "Invalid {0} name '{1}'.".format(it, nm))

                        _v = {'name': "{0}.{1}".format(schema, nm), 'table': _table,
                              'columns': ',\n'.join(["\t\t {0}".format(i.strip()) for i in ic.split(',')])}

                        file_tokens['index'].append(
                            self.db_template[ik]['create'].format(**_v))

            _constraint = objects[table].get('constraints', None)
            if _constraint:
                for _name in _constraint:
                    _cn = "{1}_{2}".format(schema, prefix, _name)

                    self.log.debug(
                        f"Validating '{_constraint[_name]['type']}' constraint '{_cn}'")

                    if not id_regexp.fullmatch(_cn):
                        raise AssertionError("Invalid {0} name '{1}'.".format(
                            _constraint[_name]['type'], _cn))
                    _ct = {
                        'table': _table,
                        'name': _cn
                    }
                    ct = _constraint[_name]['type']
                    if ct == 'primary key':
                        _ct['columns'] = ',\n'.join(
                            ["\t\t {0}".format(i) for i in _constraint[_name]['columns']])
                        file_tokens[ct].append(
                            self.db_template[ct]['create'].format(**_ct))
                    elif ct == 'foreign key':
                        _pt = _constraint[_name]['parent table']
                        _ct['parent_table'] = _pt if '.' in _pt else "{0}.{1}_{2}".format(
                            schema, prefix, _pt)
                        _ct['child_columns'] = ',\n'.join(
                            ["\t\t {0}".format(i) for i in _constraint[_name]['child columns']])
                        _ct['parent_columns'] = ',\n'.join(
                            ["\t\t {0}".format(i) for i in _constraint[_name]['parent columns']])
                        _ct['delete_action'] = _constraint[_name].get(
                            'on delete', 'cascade').lower().strip()

                        assert _ct['delete_action'] in (
                            'no action', 'restrict', 'cascade')
                        if _ct['delete_action'] == 'cascade':
                            _ct['delete_action'] = "\non delete " + \
                                                   _ct['delete_action']
                        else:
                            _ct['delete_action'] = ''

                        file_tokens[ct].append(
                            self.db_template[ct]['create'].format(**_ct))

            _seq = objects[table].get('sequence', None)
            if _seq:
                _sl = []
                _sd = self.db_template['sequence']['default']

                if isinstance(_seq, list):
                    for _sn in _seq:
                        _v = dict(name="{0}.{1}_{2}".format(
                            schema, prefix, _sn))
                        _v.update(_sd)
                        _sl.append(_v)
                elif isinstance(_seq, str):
                    _v = dict(name="{0}.{1}_{2}".format(schema, prefix, _seq))
                    _v.update(_sd)
                    _sl.append(_v)

                for sd in _sl:
                    _n = sd['name'][len(schema) + 1:]

                    self.log.debug(f"Validating sequence '{_n}'")

                    if not id_regexp.fullmatch(_n):
                        raise AssertionError(
                            "Invalid sequence name '{}'.".format(_n))
                    file_tokens['sequence'].append(
                        self.db_template['sequence']['drop'].format(**sd))
                    file_tokens['sequence'].append(
                        self.db_template['sequence']['create'].format(**sd))

            columns.update(who_column)
            columns.update(extra_columns)

            table_data = []

            for column in columns:
                # print("column : " + column)
                _type = columns[column]['type'].lower()

                self.log.debug(
                    f"Validating column {column.upper()} ({_type.upper()})")

                if _type not in data_type.keys():
                    raise AssertionError("Unsupported type {}".format(_type))
                columns[column]['name'] = column

                _token = {}
                _formats = {}
                _column = ["\t"]

                # get the columns detail
                _validations = data_type[_type]['validate']
                # _defaults = data_type[_type]['default']

                for fmt in data_type[_type]['format']:
                    _formats[fmt] = []
                    for mt in self.token_regex.findall(fmt):
                        _formats[fmt].append(mt[0])

                # self.log.debug(f"type={_type} formats={_formats}")
                # print(formats)

                _ct = dict(
                    table=_table,
                    column=column,
                    type=_type
                )

                # print(_dm.groups(), _ds, _dv)

                for _field in _validations:
                    _ct['field'] = _field
                    _ct['variable'] = columns[column].get(_field, '')

                    # print(_ct)

                    if _validations[_field]['mandatory']:
                        if _field not in columns[column]:
                            print(
                                "Required field '{field}' not defined in {table}.{column}".format(**_ct))
                        _token[_field] = columns[column][_field]
                    else:
                        if _field in columns[column]:
                            _token[_field] = columns[column][_field]
                    if _field not in _token:
                        continue

                    if not re.fullmatch(_validations[_field]['regexp'], str(columns[column][_field]),
                                        re.IGNORECASE | re.MULTILINE):
                        raise AssertionError(
                            "{variable} not allowed for '{field}' in {table}.{column}.".format(**_ct))

                    for _check in _validations[_field]:
                        _ct['check'] = _check
                        _ct['value'] = _validations[_field][_check]
                        if _check == 'min' and columns[column][_field] < _validations[_field][_check]:
                            msg = "{table}({column} {field}), {check} value is {value}, value is {variable}."
                            raise AssertionError(msg.format(**_ct))
                        if _check == 'max' and columns[column][_field] > _validations[_field][_check]:
                            msg = "{table}({column} {field}), {check} value is {value}, value is {variable}."
                            raise AssertionError(msg.format(**_ct))

                for _format, _tokens in _formats.items():
                    # self.log.debug(_format)
                    _df = set(_tokens).difference(_token)
                    _di = set(_token).difference(_tokens)

                    if len(_df) == 0 and len(_di) == 0:
                        _column.append(_format.format(**_token))
                        break
                    else:
                        continue
                    # table_data.append(_format.format(**_token))
                    # break

                if columns[column].get('constraint') or not (columns[column].get('nullable', True)):
                    _column.append("not null")
                elif columns[column].get('default'):
                    _ds = data_type[_type]['default']
                    _dv = columns[column]['default']
                    _rgx = '|'.join(_ds['regexp'])

                    if "{{" in _rgx:
                        _rgx = _rgx.format(**_token)

                    _dr = re.compile(_rgx, re.IGNORECASE | re.MULTILINE)
                    _dq = _ds.get('quote', '')
                    _ev = str(_dv).replace(_dq, _dq + _dq)
                    if not _dr.fullmatch(str(_dv)):
                        msg = "{table} ({column}, {type}, ".format(**_ct)
                        msg += "default : {quote}{value}{quote})".format(
                            value=_ev, quote=_dq)
                        raise AssertionError(msg)

                    _column.append(_ds['format'].format(value=_ev))

                table_data.append(" ".join(_column))

            tokens['name'] = "{schema}.{prefix}_{table}".format(**tokens)
            tokens['columns'] = ",\n".join(table_data)

            file_tokens['table'].append(
                self.db_template['table']['drop'].format(**tokens))
            file_tokens['table'].append(
                self.db_template['table']['create'].format(**tokens))
        # print(self.ddl_sql, self.dml_sql)

        token = {"timestamp": '{:%d-%m-%Y %H:%M:%S}'.format(datetime.now()), "version" : str(application_version)}
        for key, value in file_tokens.items():
            _key = key.replace(" ", "_")
            token[_key] = ''
            if value:
                value.insert(
                    0, "{:-^70}\n\n".format(' [ ' + key.title() + ' ] '))
                token[_key] = '\n'.join(value)

        with open(self.ddl_sql, "w", newline="\n") as wh:
            wh.write(self.db_template['ddl_script'].format(**token))
            # print("Generated DDL file : {}".format(self.ddl_sql.absolute()))
        d = dict(path=self.out_dir.absolute(),
                 color=Fore.GREEN, reset=Style.RESET_ALL)
        print("{color}SQL Resources path : {path}{reset}".format(**d))


if __name__ == '__main__':
    st = time.time()
    colorama.init()
    _default = Path()
    print(Fore.RED, end='')
    _template = Path(os.environ["FUMA_DIRECTORY"]
                     ).joinpath(r'_setup\_template.yml')
    parser = ArgumentParser(description="Autodeployment script")
    parser.add_argument("-f", "--file", default=r"D:\working\oracle\BTM\_setup\reports.yml", type=str,
                        help="Path to setup yaml file")

    args = parser.parse_args()
    print(Style.RESET_ALL, end='')
    try:
        log_level = 'warning'
        if not args.file:
            raise AssertionError("Please supply the configuration file.")
        else:
            _file = Path(args.file)
            if not (_file.exists() and _file.is_file()):
                raise AssertionError(
                    "Invalid configuration file '{}'".format(_file.absolute()))
            setup_file = _file
            with open(_file) as fh:
                config = yaml.load(fh, Loader=Loader)['config']
                log_level = config.get("log-level", 'debug').lower()
                # if config.get('debug', False):
                # debug_mode(_file)
            log = _file.with_suffix('.log')
            log.unlink(missing_ok=True)
            print("{color}Log File : {msg}{rst}".format(
                color=Fore.MAGENTA, msg=log, rst=Style.RESET_ALL))
            # _file.with_suffix('.log').unlink(missing_ok=True)
        current_date = datetime.now()
        thread_lock = threading.Lock()
        # logging = LoggingHandler(file=args.file, level=log_level)
        _threads = [threading.Thread(target=SQL, args=(args.file, _template, thread_lock, log_level)),
                    threading.Thread(target=AOL, args=(
                        args.file, _template, thread_lock, log_level)),
                    threading.Thread(target=OAF, args=(
                        args.file, _template, thread_lock, log_level)),
                    ]

        # _text = "{color}Processing {rst}".format(format(color=Fore.CYAN, msg=et - st, rst=Style.RESET_ALL))
        with Halo(text_color="cyan", spinner='star'):
            [_thread.start() for _thread in _threads]
            [_thread.join() for _thread in _threads]

        et = time.time()

        print(
            "{color}Process Complete. Took {msg:,.4f}s{rst}".format(color=Fore.GREEN, msg=et - st, rst=Style.RESET_ALL))
    except Exception as e:
        print("{color}{msg}{rst}".format(
            color=Fore.RED, msg=e, rst=Style.RESET_ALL))
