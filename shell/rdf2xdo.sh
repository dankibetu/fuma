export rdffile="SAF_PAYSLIP_ANALYSIS.rdf";
$ORACLE_HOME/bin/rwconverter apps/swara321 stype=rdffile source=$XXSFC_TOP/reports/US/$rdffile dtype=xmlfile dest=$HOME/dkibetu/rdf2xdo/$rdffile.xml batch=yes overwrite=yes;
java  oracle.apps.xdo.rdfparser.BIPBatchConversion .xml -source $HOME/dkibetu/rwconverter/2022-r -target $HOME/dkibetu/rwconverter/2022-r -debug