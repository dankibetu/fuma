Public Function FumaOracleDML(inputRange As Range, Optional MultiLine As Boolean = False) As Variant
    Dim result() As Variant
    Dim DML As String
    Dim regex As Object
    Dim colTitles() As String
    Dim rowCounter As Integer
    Dim colCounter As Integer
    Dim colCount As Integer
    Dim rowCount As Integer
    Dim valuesArray() As String

    Set regex = CreateObject("VBScript.RegExp")
    regex.Pattern = "[^a-zA-Z0-9_]"
    regex.Global = True

    colCount = inputRange.Columns.Count
    rowCount = inputRange.Rows.Count
    ReDim result(1 To rowCount - 1, 1 To 1)
    ReDim colTitles(1 To colCount)

    ' Store processed column titles once
    For colCounter = 1 To colCount
        colTitles(colCounter) = regex.Replace(inputRange.Cells(1, colCounter).Value, "_")
    Next colCounter

    ' Iterate over rows starting from row 2 (data rows)
    For rowCounter = 2 To rowCount
        ' Determine UNION ALL for subsequent rows
        If rowCounter = 2 Then
            DML = "SELECT "
        Else
            DML = "UNION ALL SELECT "
        End If

        If MultiLine Then
            DML = DML & vbCrLf
        End If

        ' Prepare column values
        ReDim valuesArray(1 To colCount)

        For colCounter = 1 To colCount
            Dim val As String
            Dim cell As Range
            Set cell = inputRange.Cells(rowCounter, colCounter)
            
            ' Identify cell format
            Dim cellFormat As String
            cellFormat = cell.NumberFormat
            
            ' Normalize date format variations
            Dim isDateFormat As Boolean
            isDateFormat = (InStr(cellFormat, "d") > 0 Or InStr(cellFormat, "m") > 0 Or InStr(cellFormat, "y") > 0 Or InStr(cellFormat, "h") > 0)

            ' Check if numeric format
            Dim isNumericFormat As Boolean
            isNumericFormat = (IsNumeric(cell.Value) And Not isDateFormat)

            ' Check if text format (Excel stores "@" as Text format)
            Dim isTextFormat As Boolean
            isTextFormat = (cellFormat = "@" Or Application.WorksheetFunction.IsText(cell.Value))

            ' Process cell value
            If IsEmpty(cell.Value) Then
                ' Handle NULL values
                If isDateFormat Then
                    val = "TO_DATE(NULL)"
                ElseIf isNumericFormat Then
                    val = "TO_NUMBER(NULL)"
                Else
                    val = "TO_CHAR(NULL)" ' Text NULL values
                End If
            ElseIf isDateFormat Then
                ' Handle Date values with time part
                val = "TO_DATE('" & Format(cell.Value, "YYYY-MM-DD HH24:MI:SS") & "', 'YYYY-MM-DD HH24:MI:SS')"
            ElseIf isNumericFormat And Not isTextFormat Then
                ' Handle numeric values (if NOT formatted as text)
                val = cell.Value
            Else
                ' If text format OR a number stored in a text column
                val = "q'[" & cell.Text & "]'"
            End If
            
            valuesArray(colCounter) = val & " AS " & colTitles(colCounter)
        Next colCounter

        ' Join values into a formatted SQL statement
        DML = DML & Join(valuesArray, ", ")

        If MultiLine Then
            DML = DML & vbCrLf
        End If

        DML = DML & " FROM DUAL"

        ' Store result
        result(rowCounter - 1, 1) = DML
    Next rowCounter

    ' Return the generated SQL statements
    FumaOracleDML = result
End Function
