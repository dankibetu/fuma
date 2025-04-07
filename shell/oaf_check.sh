cat $FND_TOP/admin/template/ebsProductManifest_xml.tmp

adjava oracle.apps.ad.jri.adjmx -areas $JAVA_TOP/customall.zip -outputFile $JAVA_TOP/customall.jar -jar $CONTEXT_NAME 1 CUST jarsigner