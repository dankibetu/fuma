import os
import re
from collections import OrderedDict
from pprint import pprint

import ruamel.yaml
from yamlordereddictloader import Dumper

__acronym__ = r'xxsfc.euda_'

__pass__ = re.compile(r'^((drop|(alter.+drop)).+;$)|(--)+', re.I)
__tbl__ = re.compile(r'^create table {}([\w]+)\($'.format(__acronym__), re.I)
__cols__ = re.compile(
    r"^([\w]+)[\s]+(varchar2|date|number|blob|clob)(?:\((\d+)\))?(?:[\s]+)?(?:default[\s]+(?:')?([\w-]+)(?:')?,)?(not null)?")
__constraints__ = re.compile(
    r'^alter[\s]+table[\s]+(?:{accronym}(\w+))[\s]+add[\s]+constraint[\s]+(\w+)[\s]+(\w+[\s]+\w+)[\s]+[(]([\w,\s]+)(?:[)\s]+references[\s]+{accronym}(\w+)[\s(]+)?(?:([\w\s,]+)(?:\)[\s]+.+))?(?:\))?;'.format(accronym=__acronym__))
__indexes__ = re.compile(
    r'^create[\s]+(?:(unique)[\s]+)?index[\w\s.]+{accronym}(\w+)[\s]+\(([\w,\s]+)\);'.format(accronym=__acronym__))
__alter_statement__ = re.compile(r'^(?:alter[\s+]table.+)', re.I)
__eol__ = re.compile(r';', re.I | re.M)
__mapping__ = ['type', 'length', 'default', 'column_attribute']

__defaults__ = OrderedDict({'attribute columns': [
    {'count': 1, 'field': {'column': 'attribute_category',
                           'type': 'varchar2', 'length': 50}},
    OrderedDict({'count': 15, 'field': {'column': 'attribute{}',
                                        'type': 'varchar2', 'length': 100}}),
    OrderedDict(
        {'count': 15, 'field': {'column': 'segment{}', 'type': 'number'}}),
],
    'who columns': [
        OrderedDict({'column': 'created_by', 'type': 'number', 'default': -1}),
        OrderedDict({'column': 'last_updated_by',
                     'type': 'number', 'default': -1}),
        OrderedDict({'column': 'last_update_login',
                     'type': 'number', 'default': -1}),
        OrderedDict({'column': 'creation_date',
                     'type': 'date', 'default': 'sysdate'}),
        OrderedDict({'column': 'last_update_date',
                     'type': 'date', 'default': 'sysdate'}),
]})


class MyRepresenter(ruamel.yaml.representer.RoundTripRepresenter):
    pass


def get_file(file):
    objects = OrderedDict()
    out_file = os.path.join(os.path.dirname(file), 'reversed_db_objects.yml')
    with open(file, 'r') as fh:
        is_attribute = False
        table_name = None
        constraint = []
        is_constraint = False

        for _, line in enumerate(fh.readlines()):
            if __pass__.match(line):
                continue
            if line.startswith("created_by"):
                is_attribute = True
                objects[table_name]['has_attribute_columns'] = True
            if line.startswith(");"):
                is_attribute = False
                table_name = None
                continue
            if(is_attribute):
                continue

            if table_name:
                attrs = __cols__.findall(line)
                _col_name = None

                for index, attr in enumerate(attrs[-1]):
                    if index == 0:
                        _col_name = attr
                        objects[table_name]['columns'].setdefault(
                            _col_name, OrderedDict())
                    else:
                        if attr:
                            objects[table_name]['columns'][_col_name][__mapping__[
                                index-1]] = int(attr) if (index == 3 and attrs[-1][1] == 'number') or (index == 2) else attr

            if __tbl__.match(line):
                table_name = __tbl__.search(line).group(1)
                objects.setdefault(
                    table_name, OrderedDict(columns=OrderedDict()))

            if __alter_statement__.match(line):
                is_constraint = True

            if is_constraint:
                constraint.append(line)

            if __eol__.search(line) and is_constraint:
                is_constraint = False
                attrs = __constraints__.findall(''.join(constraint))
                info = OrderedDict(type=attrs[0][2])

                if 'primary' in attrs[0][2]:
                    info['columns'] = [i.strip()
                                       for i in attrs[0][3].split(',')]
                else:
                    info['child columns'] = [i.strip()
                                             for i in attrs[0][3].split(',')]
                    info['parent table'] = attrs[0][4]
                    info['parent columns'] = [i.strip()
                                              for i in attrs[0][5].split(',')]

                objects[attrs[0][0]].setdefault('constraints', OrderedDict())
                objects[attrs[0][0]]['constraints']['_'.join(
                    attrs[0][1].split('_')[1:])] = info
                constraint = []

            if __indexes__.match(line):
                attrs = __indexes__.findall(line)
                _index = attrs[0][0] or 'normal'
                objects[attrs[0][1]].setdefault('index', OrderedDict())
                objects[attrs[0][1]]['index'].setdefault(_index, [])
                objects[attrs[0][1]]['index'][_index].append(attrs[0][2])

    with open(out_file, 'w') as fh:
        fl = OrderedDict(tables=objects)
        fl.update(__defaults__)

        ruamel.yaml.add_representer(OrderedDict, MyRepresenter.represent_dict,
                                    representer=MyRepresenter)

        yaml = ruamel.yaml.YAML()
        yaml.Representer = MyRepresenter
        yaml.indent(mapping=4, sequence=5, offset=2)
        yaml.dump(fl, fh)


if __name__ == "__main__":
    file = os.path.join(r'D:\projects_working\Laptop Policy\development\_queries',
                        'euda_db_objects.sql')
    get_file(file)
