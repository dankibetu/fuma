Public Function FumaOracleDML(inputRange As Range, Optional MultiLine As Boolean = False) As Variant
    Dim result() As Variant
    Dim dml As String
    Dim regex As Object
    
    Set regex = CreateObject("VBScript.RegExp")
    regex.Pattern = "[^a-zA-Z0-9_]"
    regex.Global = True
    
    'Dim colTitle() As Variant
    
    'ReDim colTitle(1 To inputRange.Columns.Count)
    ReDim result(1 To inputRange.Rows.Count - 1, 1 To 1)
    
    Dim rowCounter As Integer
    Dim colCounter As Integer
    
    'The first row is considered the titles
    For rowCounter = 2 To inputRange.Rows.Count
        'Reset for the next Interation
        If rowCounter > 2 Then
            dml = "UNION ALL SELECT "
        Else
            dml = "SELECT "
        End If
        
        If MultiLine Then
            dml = dml & vbCrLf
        End If
        
        For colCounter = 1 To inputRange.Columns.Count
            'Check the data type to use
            Dim val As String
            Dim title As String
            
            'If colCounter >= LBound(colTitle) And colCounter <= UBound(colTitle) Then
            '   title = colTitle(colCounter)
            'Else
            '    title = inputRange.Cells(1, colCounter).Value
            '
            '    colTitle(colCounter) = title
            'End If
            
            title = regex.Replace(inputRange.Cells(1, colCounter).Value, "_")
            
                        
            If IsEmpty(inputRange.Cells(rowCounter, colCounter).Value) Then
                val = "NULL"
             ElseIf IsNumeric(inputRange.Cells(rowCounter, colCounter).Value) Then
                If VarType(inputRange.Cells(rowCounter, colCounter).Value) = vbString Then
                    val = "q'[" & inputRange.Cells(rowCounter, colCounter).Value & "]'"
                Else
                    val = inputRange.Cells(rowCounter, colCounter).Value
                End If
            ElseIf IsDate(inputRange.Cells(rowCounter, colCounter).Value) Then
                val = "TO_DATE('" & Format(inputRange.Cells(rowCounter, colCounter).Value, "DD-MM-YYYY") & "', 'DD-MM-YYYY')"
                
            Else
                val = "q'[" & inputRange.Cells(rowCounter, colCounter).Value & "]'"
            End If
            
            If MultiLine Then
                dml = dml & vbTab
            End If
            
             dml = dml & val & " AS " & title
            
            If colCounter = inputRange.Columns.Count Then
                If MultiLine Then
                    dml = dml & vbCrLf
                End If
                
                dml = dml & " FROM DUAL"
            Else
                dml = dml & " , "
            End If
           
            If MultiLine Then
                dml = dml & vbCrLf
            End If
            
        Next colCounter
        result(rowCounter - 1, 1) = dml
        
    Next rowCounter
    
    
    FumaOracleDML = result
    
        
End Function

