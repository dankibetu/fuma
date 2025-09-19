import yaml
from getpass import getpass
from argparse import ArgumentParser
from keyring import get_password, set_password, get_credential, delete_password


def get_environment():
    _instances = []
    _view = 'N'
    _new = True
    try:
        while True:
            if not _new:
                _create = input(
                    "Would you like to add another environment? [Y/N]: ").lower()
                if not (len(_create) > 0 and _create.startswith('y')):
                    break
            _count = len(_instances) + 1
            _env = input(f"Oracle EBS Instance {_count} Name : ").upper()
            _view = input(f"View password as you type? [{_view}]: ").upper()
            _echo = (_view and _view.startswith('Y'))
            _default_db_user = 'APPS'
            _db_user = input(f"\t'{_env}' Database username : [{_default_db_user}] : ")
            if not _db_user:
                _db_user = _default_db_user
            if _echo:
                _db_pass = input(f"\t'{_env}' Database '{_db_user}' password : ")
            else:
                _db_pass = getpass(f"\t'{_env}' Database '{_db_user}' password : ")
            _os_user = input(f"\t'{_env}' Application Server username : ")
            if _echo:
                _os_pass = input(f"\t'{_env}' Application Server '{_os_user}' password : ")
            else:
                _os_pass = getpass(f"\t'{_env}' Application Server '{_os_user}' password : ")
            _instances.append(dict(name=_env, os=dict(username=_os_user, password=_os_pass), db=dict(
                username=_db_user, password=_db_pass
            )))
            _new = False
    except Exception as e_m:
        print(f"{e_m}")

    return _instances


if __name__ == '__main__':
    _environments = []
    parser = ArgumentParser(description="Credentials Setup")
    parser.add_argument("-a", "--action", required=True, type=str, choices=[
        "get", "set", "delete"], help="action to execute : [set/get/delete]")
    parser.add_argument("-c", "--config", type=str, help="yaml configuration")
    parser.add_argument("-l", "--login", type=str,
                        action="append", help="login to lookup")
    parser.add_argument("-i", "--instance", type=str,
                        action="append", help="Environment instance")

    args = parser.parse_args()

    # if not args.action or args.action.lower() not in ('set', 'get', 'delete'):
    #     raise AssertionError("Please enter valid action to execute : [set/get]")
    if args.action.lower() in ('set'):
        if not args.config:
            _environments = get_environment()
        else:
            try:
                _environments = yaml.safe_load(args.config)
            except Exception as e:
                raise AssertionError(f"Please enter valid configuration : {e}")
    if args.action.lower() in ('get', 'delete') and not args.login:
        raise AssertionError("Please enter valid login")

    _domains = ['DB', 'OS']
    _credential = 'FUMA'

    if args.action.lower() == 'set':
        # _config =
        for config in _environments:
            for _domain in _domains:
                _name = f"{_credential}_{config.get('name').upper()}_{_domain}"
                _user = config[_domain.lower()]['username']
                _pass = config[_domain.lower()]['password']
                # try :
                #     delete_password(_name, _user)
                # except Exception as e :
                #     print(f"Unable to delete {config.get('name').upper()} {_domain} credentials")
                set_password(_name, _user, _pass)
                print(f"{_name} Credentials created : {_user}/***")

        # print(config)
    elif args.action.lower() == 'get':
        # print(args.login)
        for login in args.login:
            for _domain in _domains:
                _name = f"{_credential}_{login.upper()}_{_domain}"
                _login = get_credential(_name, None)
                if _login:
                    print(
                        f"{login.upper()} [{_domain}] : {_login.username}/{_login.password}")
                else:
                    print(f"{login.upper()} [{_domain}] : Unable to resolve")
    elif args.action.lower() == 'delete':
        for login in args.login:
            for _domain in _domains:
                _name = f"{_credential}_{login.upper()}_{_domain}"
                _login = get_credential(_name, None)
                if _login:
                    delete_password(_name, _login.username)
                    print(f"{login.upper()} [{_domain}] : Credential deleted")
                else:
                    print(f"{login.upper()} [{_domain}] : Unable to resolve")
