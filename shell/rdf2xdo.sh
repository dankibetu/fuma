export xmldest="${HOME}/NextTechnologies/dkibetu/rdf2xdo";
export rdffile="NCWSC_PAYSLIP_RPT.rdf";
mkdir -p $xmldest/rwconverter;
mkdir -p $xmldest/xdo;
cd $xmldest;
cp $PAY_TOP/reports/US/$rdffile .;
$ORACLE_HOME/bin/rwconverter APPS/welcome1 stype=rdffile source=./$rdffile dtype=xmlfile dest="rwconverter/$rdffile.xml" batch=yes overwrite=yes;
java  oracle.apps.xdo.rdfparser.BIPBatchConversion .xml -source ./rwconverter -target ./xdo -debug