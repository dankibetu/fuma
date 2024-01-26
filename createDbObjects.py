import os
import re
import time
import traceback
from collections import OrderedDict as OD

import colorama
import yaml
from colorama import Back, Fore, Style
from yamlordereddictloader import Loader as loader
import subprocess
import io

colorama.init()

_drop_objects = True
schema = None
accronym = None
short_name = None
db_script = None
init_script = None

init_out_file = None
out_file = None
out_dir = None


field_format = ''
_comment = '-- ' if not _drop_objects else ''


__VERSION__ = 'v2.1.78'
__IDENTIFIER_LENGTH__ = 30
__REG_EXP__ = re.compile(r"^([-+]?(\d)+)|(sysdate)$", re.I)
__TRUNCATE_TABLES__ = None

__INVERT_EXCL_TBL_SEL__ = None
__WORKING__ = None
__PROJECT__ = None
__ZIP_LOCATION__ = None
__OAF_PROJECT_DIR__ = None
__BACKUP_LOCATION__ = None
__EXCLUSIVE_TABLES__ = []
__INIT_EXCLUSIVE_TBL__ = []


template_file = os.path.join(os.path.dirname(
    os.path.realpath(__file__)), '_setup', 'templates.yml')

__NOT_NUMBER__ = re.compile(r'[^\d.]+')


def oaf_deployment_script():
    assert __ZIP_LOCATION__ is not None
    g_files = ''
    shell_file = os.path.join(
        __ZIP_LOCATION__, 'import_{}.sh'.format(__WORKING__))
    explorer_command = r'explorer /select,"{}"'.format(
        os.path.join(__ZIP_LOCATION__, __WORKING__))
    for root, _, files in os.walk(os.path.join(__OAF_PROJECT_DIR__, __PROJECT__, __WORKING__), topdown=False):
        for name in files:
            if name.upper().endswith(('PG.XML', 'RN.XML')):
                file_name = os.path.join(root, name)[len(__OAF_PROJECT_DIR__):]
                g_files += '\n\t"{file}"'.format(
                    file=file_name).replace('\\', '/')

    template = get_template()["shell_script"]
    _ty = ['APPS-DEV', 'APPS-DATA', 'APPS-PREP']
    _subs = dict(FILES=g_files,
                 file_name=os.path.basename(shell_file),
                 zip_file=__WORKING__,
                 project=__PROJECT__.replace('\\', '/'),
                 time_generated=time.strftime('%d-%b-%Y %H:%M:%S', time.localtime()))

    for _t in _ty:
        _subs.setdefault(_t, os.environ[_t])

    # print(_subs)

    with io.open(shell_file, 'w', newline='\n') as fh:

        fh.write(template.format(**_subs))
    subprocess.Popen(explorer_command)


def validate():
    assert db_script is not None
    assert os.path.exists(db_script)
    assert os.path.exists(template_file)
    if init_script:
        assert os.path.exists(init_script)


def run(_objects_script, _data_script,  drop=True, oaf_location=None, oaf_deployment=False, truncate=False, _exc_table=[], _exc_data=[], _invert=False):
    global _drop_objects
    global db_script
    global init_script
    global out_dir
    global __OAF_PROJECT_DIR__
    global __TRUNCATE_TABLES__
    global __BACKUP_LOCATION__
    global __EXCLUSIVE_TABLES__
    global __INIT_EXCLUSIVE_TBL__
    global __INVERT_EXCL_TBL_SEL__

    db_script = _objects_script
    init_script = _data_script
    _drop_objects = drop

    __OAF_PROJECT_DIR__ = oaf_location
    __EXCLUSIVE_TABLES__ = _exc_table
    __INIT_EXCLUSIVE_TBL__ = _exc_data
    __BACKUP_LOCATION__ = os.path.join(os.path.dirname(
        os.path.dirname(db_script)), '_backup')
    __TRUNCATE_TABLES__ = truncate
    __INVERT_EXCL_TBL_SEL__ = _invert

    validate()

    out_dir = os.path.join(os.path.dirname(
        os.path.dirname(db_script)), '_queries')

    paths = [__BACKUP_LOCATION__, out_dir]

    [os.makedirs(_loc, exist_ok=True) for _loc in paths]

    out_file = get_db_objects()
    print("{}[Database Objects] : Process completed successfully.\n\tOutput : {}{}{}".format(
        Fore.GREEN, '', out_file, Style.RESET_ALL))

    if init_script:
        init_out_file = get_init_data()
        if init_out_file:
            print("{}[Initialization Data] Process completed successfully.\n\tOutput : {}{}".format(
                Fore.GREEN, init_out_file, Style.RESET_ALL))

    if oaf_deployment and oaf_location:
        oaf_deployment_script()
        print("{}[OAF Deployment Script] Process completed successfully.\n\tOutput : {}{}".format(
            Fore.GREEN, __ZIP_LOCATION__, Style.RESET_ALL))


def get_template():
    global field_format
    with open(template_file) as th:
        _template = yaml.safe_load(th)
        field_format = _template['field format']
    return _template


def get_column_info(info):
    global field_format
    info.setdefault('left_brace', None)
    info.setdefault('length', None)
    info.setdefault('default', None)
    info.setdefault('right_brace', None)
    info.setdefault('column_attribute', None)
    info.setdefault('default_placeholder', None)
    if info.get('length'):
        info['left_brace'] = '('
        info['right_brace'] = ')'
    if info.get('default', None) is not None:
        info['default_placeholder'] = 'default'
    fs = {}
    for k, v in info.items():
        fs[k] = v if v is not None else ''

    default_val = ("{}".format(fs['default']).lower()) or None
    if default_val is not None:
        if __REG_EXP__.match(default_val):
            fs['default'] = "{}".format(fs['default'])
        else:
            fs['default'] = "'{}'".format(fs['default'])

    return field_format.format(**fs)


def generate_attribute_columns(cols, attr_len=None, attrs={}):
    fields = ''
    for col in cols:
        field = col.get('field', {})

        column = field.get('column', None)
        if column.endswith('{}'):
            _len = attrs.get(column[:-2])
            # if attr_len is not None:
            loops = _len or attr_len or col.get('count', 0)
        else:
            loops = col.get('count', 0)
        for i in range(loops):
            fv = field['column']
            field['column'] = fv.format(i + 1)
            fields += '\t'+get_column_info(field).strip() + ',\n'
            field['column'] = fv
    return fields


def get_columns(cols, attrs={}):
    col_details = []
    for col in cols:
        fb = {'count': 1, 'field': col}
        col_details.append(fb)
    return generate_attribute_columns(col_details, None, attrs)


def get_db_objects():
    global schema
    global accronym
    global short_name
    global __WORKING__
    global __PROJECT__
    global __ZIP_LOCATION__
    global __INVERT_EXCL_TBL_SEL__

    _objects = ''
    templates = get_template()
    try:
        with open(db_script, 'r') as script_handle:
            loaded_objects = yaml.load(script_handle, Loader=loader)

            schema = loaded_objects['config']['schema']
            accronym = loaded_objects['config']['prefix']
            short_name = loaded_objects['config']['initials']
            oaf_project = loaded_objects['config'].get('oaf')
            if oaf_project and __OAF_PROJECT_DIR__:
                __PROJECT__ = os.path.dirname(oaf_project["package"].replace(".", "\\").format(
                    **oaf_project))
                __ZIP_LOCATION__ = os.path.join(
                    os.path.dirname(__OAF_PROJECT_DIR__), 'myclasses', __PROJECT__)
                __WORKING__ = oaf_project.get('component', oaf_project.get(
                    'project'))  # "{project}".format(**oaf_project)

            who_columns = list(loaded_objects['who columns'])
            directories = loaded_objects.get('directories', [])
            _trigger = loaded_objects.get('triggers', OD(
                {'info': ['-- No Trigger Information was defined.']}))

            attribute_columns = list(loaded_objects['attribute columns'])
            loaded_table = loaded_objects['tables']
            _indexes = ''
            _tables = ''
            _sequences = ''
            _constraints = ''
            _synonyms = ''
            _primary_keys = ''
            _directories = ''

            for dir in directories:
                _directories += templates.get('directory').format(
                    **dict(name=dir.upper(), path=directories.get(dir))
                )

            for tbl in loaded_table:
                if __EXCLUSIVE_TABLES__ and (
                        (not __INVERT_EXCL_TBL_SEL__ and tbl not in __EXCLUSIVE_TABLES__)
                        or (__INVERT_EXCL_TBL_SEL__ and tbl in __EXCLUSIVE_TABLES__)
                ):
                    try:
                        del _trigger[tbl]
                    except KeyError:
                        pass
                    # print(tbl)
                    # print(__INVERT_EXCL_TBL_SEL__)
                    continue

                _table_name = "{}_{}".format(accronym, tbl)
                if len(_table_name) >= __IDENTIFIER_LENGTH__:
                    raise AssertionError(
                        "ORA-00972: identifier is too long ({} characters) [Table Name - {}.{}]".format(len(_table_name), schema, _table_name))
                td = {'schema': schema, 'accronym': accronym, 'comment': _comment,
                      'table': tbl, 'columns': ''}
                sd = {'schema': schema, 'accronym': accronym, 'comment': _comment,
                      'sequence': ''}
                id = {'schema': schema, 'accronym': accronym, 'short name': short_name, 'comment': _comment,
                      'type': '', 'name': 'I', 'columns': '', 'table': tbl}
                cd = {'schema': schema, 'accronym': accronym,
                      'table': tbl, 'comment': _comment}
                syn = {'schema': schema, 'accronym': accronym,
                       'table': tbl, }

                _has_pk_ = '-- '
                _pk_info_ = None
                _pk_name_ = None
                _desc = loaded_table[tbl].get('description')
                columns = loaded_table[tbl]['columns']
                col_list = []
                for col in columns:
                    col_attr = columns[col].get('column_attribute', 'none')
                    if col_attr.lower().strip().endswith('primary key'):
                        columns[col]['column_attribute'] = 'not null'
                        _has_pk_ = ''
                        _pk_name_ = '{}_pk'.format(tbl)
                        if not _pk_info_:
                            _pk_info_ = {_pk_name_: {
                                'type': col_attr, 'columns': [col]}}
                        else:
                            _pk_info_[_pk_name_]['columns'].append(col)

                    col_detail = dict(columns[col])
                    col_detail.setdefault('length', None)
                    col_detail.setdefault('default', None)
                    col_detail.setdefault(
                        'column_attribute', col_detail.get('constraint', None))
                    if 'char' in col_detail['type'] and not col_detail.get('length'):
                        raise AssertionError(
                            '{}ORA-00906: missing length for {}.{} {}(?){}'.format(
                                Fore.RED, tbl, col, col_detail['type'], Style.RESET_ALL)
                        )
                    if len(col) >= __IDENTIFIER_LENGTH__:
                        raise AssertionError(
                            "{}ORA-00972: identifier is too long ({} characters) [Column - {}.{}({})]{}".format(Fore.RED, len(col), schema, _table_name, col, Style.RESET_ALL))

                    col_detail['column'] = col
                    col_list.append(col_detail)

                cols = get_columns(col_list) + get_columns(who_columns)

                if loaded_table[tbl].get('constraints', _pk_info_):
                    try:
                        constraints = loaded_table[tbl].get('constraints')

                        if(constraints and _pk_info_):
                            constraints.update(_pk_info_)
                            constraints.move_to_end(_pk_name_, last=False)
                        elif(_pk_info_):
                            constraints = _pk_info_

                        for constraint in constraints:

                            cd['name'] = "{}_{}".format(short_name, constraint)
                            # print(constraints[constraint])
                            template = templates.get( constraints[constraint]['type'], '')
                            

                            if constraints[constraint]['type'].lower().strip().endswith('primary key'):
                                _has_pk_ = ''
                                cd['columns'] = ', '.join(constraints[constraint].get(
                                    'columns', []))
                                _primary_keys += template.format(**cd)

                            else:
                                cd['child_columns'] = ', '.join(
                                    constraints[constraint].get('child columns', []))
                                cd['parent_columns'] = ', '.join(
                                    constraints[constraint].get('parent columns', []))
                                # {schema}.{accronym}_
                                pt_ref = "{}.{}_".format(schema, accronym) if constraints[constraint].get(
                                    'local', True) else ''
                                cd['parent_table'] = "{}{}".format(
                                    pt_ref, constraints[constraint].get('parent table'))
                                cd['restrict'] = '\non delete cascade' if constraints[constraint].get(
                                    'cascade', True) else ''

                                _constraints += template.format(**cd)

                    except Exception as e:
                        print(tbl)
                        print(traceback.format_exc())
                        

                if loaded_table[tbl].get('has_synonym'):
                    _synonyms += templates['synonym'].format(**syn)

                if loaded_table[tbl].get('has_attribute_columns', True):
                    attribute_len = loaded_table[tbl].get(
                        'attribute_length')
                    cols += generate_attribute_columns(
                        attribute_columns, attribute_len, dict(
                            segment=loaded_table[tbl].get('segments'),
                            attribute=loaded_table[tbl].get('attributes'),
                        ))

                td['columns'] = cols[:-2]
                td['drop_pk'] = _has_pk_

                indx = loaded_table[tbl].get(
                    "index", dict(normal=[], unique=[]))
                ui = indx.get('unique')
                ni = indx.get('normal')

                if ui:
                    if isinstance(ui, list):
                        for x, y in enumerate(ui):
                            id['name'] = 'u{}'.format(x+1)
                            id['type'] = 'unique'
                            id['columns'] = y  # ', '.join(ui)
                            _indexes += templates['index'].format(**id)
                    else:
                        for _i, _k in enumerate(ui):
                            id['name'] = 'u{}'.format(_i+1)
                            id['type'] = 'unique'
                            id['columns'] = ', '.join(ui[_k])
                            _indexes += templates['index'].format(**id)

                if ni:
                    for i, c in enumerate(ni):
                        id['name'] = 'i{}'.format(i+1)
                        id['type'] = ''
                        id['columns'] = c
                        _indexes += templates['index'].format(**id)
                _tables += "/*\n{}*/\n".format(_desc) if _desc else ''
                _tables += (templates['table'].format(**td))
                if loaded_table[tbl].get('sequence', None):
                    _so2 = OD({'name': None, 'start': 1, 'increment': 1})
                    _so1 = loaded_table[tbl].get('sequence', None)
                    _ls1 = True
                    # if isinstance(_so1)
                    if(isinstance(_so1, OD)):
                        _so2.update(_so1)
                    elif isinstance(_so1, list):
                        _ls1 = False
                        for _xc in _so1:
                            _so2['name'] = _xc
                            _so2.update(sd)
                            _sequences += templates['sequence'].format(**_so2)

                    elif isinstance(_so1, str):
                        _so2['name'] = _so1
                    # sd['sequence'] = loaded_table[tbl].get('sequence', None)
                    # sd['sequence'] = _so2
                    if _ls1:
                        _so2.update(sd)
                        _sequences += templates['sequence'].format(**_so2)
            _lcTrigger = ""
            for _lti in _trigger:
                _lcTrigger += "-- Trigger Definition : Table {}\n{}\n".format(
                    _lti, ''.join(_trigger[_lti]))

            _objects = templates['file format'].format(
                **dict(triggers=_lcTrigger, version=__VERSION__, tables=_tables, directories=_directories, synonyms=_synonyms, sequences=_sequences, indexes=_indexes, constraints=_constraints, primary_key=_primary_keys, time_generated=time.strftime('%d-%b-%Y %H:%M:%S', time.localtime())))

        out_file = os.path.join(out_dir, '{}_db_objects.sql'.format(accronym))
        with open(out_file, 'w') as out_handle:
            out_handle.write(_objects)
        return out_file
    except Exception as e:
        # print(e)
        # print(e)
        print(traceback.format_exc())


def get_sequence(tbl):
    with open(db_script, 'r') as script_handle:
        table = yaml.load(script_handle, Loader=loader)['tables'][tbl]
        return "{}.{}_{}.nextval".format(schema, accronym, table['sequence'])


def get_init_value(value, table=None, total=None):
    tf = str(value).split('|')
    r = "'{}'"
    t = tf[0].strip().lower()

    if t.endswith(('sysdate')):
        r = "{}"
    elif t.endswith(('auto-number', 'sequence', 'nextval')):
        r = "{}".format(get_sequence(table))

    val = r.format(tf[0]).strip()

    try:
        f = tf[1].strip().lower()

        if f.startswith('t'):
            val = val.title()
        elif f.startswith('u'):
            val = val.upper()
        elif f.startswith('d'):
            val = 'to_date({})'.format(val)
        elif f.startswith('l'):
            val = val.lower()
        elif f.startswith('o'):
            val = "'{}.{}_{}'".format(schema, accronym, t).upper()
        elif f.startswith('n'):
            val = float(__NOT_NUMBER__.sub('', val))
            if 't' in f:
                total += val
            if 'i' in f:
                val = int(val)
                total = int(total)

        else:
            val = '{}'.format(tf[0]).strip()
    except ValueError:
        val = t.format(total=total)
    except:
        pass
    val = 'null' if value is None else val
    return (val, total)


def get_init_data():
    tmplt = get_template()

    template = tmplt["init data"]
    structure = tmplt["data structure"]
    truncate_tbl = tmplt["truncate table"]
    data = ''
    tbls = set()
    truncate = ''

    _blocks = ''
    _methods = ''
    _comment = '-- '

    with open(init_script, 'r') as script_handle:
        loaded_objects = yaml.load(script_handle, Loader=loader)
        if loaded_objects is None:
            return
        for tbl in loaded_objects:
            if __EXCLUSIVE_TABLES__ and (
                        (not __INVERT_EXCL_TBL_SEL__ and tbl not in __EXCLUSIVE_TABLES__)
                        or (__INVERT_EXCL_TBL_SEL__ and tbl in __EXCLUSIVE_TABLES__)
                ):
            # if __INIT_EXCLUSIVE_TBL__ and tbl not in __INIT_EXCLUSIVE_TBL__:
                continue
            if tbl.strip().lower().startswith(('plsql')):
                _pkg = loaded_objects[tbl]['package']
                _prc = loaded_objects[tbl]['procedure']
                _recs = loaded_objects[tbl]['records']

                for _rec in _recs:
                    _params = []
                    _total = 0
                    for _param, _val in _rec.items():
                        _pval, _total = get_init_value(_val, None, _total)
                        _params.append(
                            tmplt['plsql value'].format(label=_param, value=_pval))

                    _methods += tmplt['plsql procedure'].format(
                        package=_pkg,
                        procedure=_prc,
                        records='\t,'.join(_params)
                    )

                continue
            _comment = ''
            tbls.add(tbl)
            for cols in loaded_objects[tbl]:
                labels = []
                values = []
                _total = 0
                for col in cols:
                    if cols[col] is not None:
                        val, _total = get_init_value(cols[col], tbl, _total)
                    else:
                        val = 'null'

                    labels.append(col)
                    values.append(str(val))

                td = {'schema': schema, 'accronym': accronym, 'table': tbl,
                      'columns': ",\n\t".join(labels),
                      'values': ",\n\t".join(values)}
                data += template.format(**td)

    init_out_file = os.path.join(
        out_dir, '{}_initialization_data.sql'.format(accronym))

    for tbl in tbls:
        trunc_data = {'comment': '' if __TRUNCATE_TABLES__ else '--',
                      'schema': schema, 'accronym': accronym, 'table': tbl}

        truncate += truncate_tbl.format(
            **trunc_data
        )
    if _methods:
        _blocks += tmplt['plsql block'].format(
            blocks=_methods
        )

    with open(init_out_file, 'w') as fh:
        info = dict(
            records=data,
            version=__VERSION__,
            truncate=truncate,
            plsql=_blocks,
            comment=_comment,
            time_generated=time.strftime('%d-%b-%Y %H:%M:%S', time.localtime())
        )
        fh.write(structure.format(**info))
    return init_out_file
