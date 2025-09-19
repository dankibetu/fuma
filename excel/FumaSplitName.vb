Public Function FumaSplitName(fullName As String, Optional delimiters As String = " ", Optional returnWord As Integer = 0) As Variant
    Dim nameParts() As String
    Dim countParts As Integer
    Dim result(1 To 3) As String
    Dim i As Integer
    Dim middle As String
    Dim tempName As String
    Dim delimiter As String
    Dim j As Integer

    ' Convert user-provided escape sequences to actual characters
    delimiters = Replace(delimiters, "\t", vbTab) ' Convert \t to Tab
    delimiters = Replace(delimiters, "\n", vbLf)  ' Convert \n to Line Feed (LF)
    delimiters = Replace(delimiters, "\r", vbCr)  ' Convert \r to Carriage Return (CR)

    ' Replace all specified delimiters with a space
    For j = 1 To Len(delimiters)
        delimiter = Mid(delimiters, j, 1)
        fullName = Replace(fullName, delimiter, " ")
    Next j

    ' Remove extra spaces
    fullName = Application.WorksheetFunction.Trim(fullName)

    ' If the string is empty, return three empty strings
    If fullName = "" Then
        result(1) = ""
        result(2) = ""
        result(3) = ""
        GoTo OutputResult
    End If

    ' Split the name into parts using space as the delimiter
    nameParts = Split(fullName, " ")
    countParts = UBound(nameParts) - LBound(nameParts) + 1

    Select Case countParts
        Case 1
            ' Only one word: treat it as the last name
            result(1) = ""
            result(2) = ""
            result(3) = nameParts(0)
        Case 2
            ' Two words: first name and last name only
            result(1) = nameParts(0)
            result(2) = ""
            result(3) = nameParts(1)
        Case Else
            ' Three or more words: first is first name, last is last name, middle is everything in between
            result(1) = nameParts(0)
            middle = ""
            For i = 1 To countParts - 2
                middle = middle & nameParts(i)
                If i < countParts - 2 Then
                    middle = middle & " "
                End If
            Next i
            result(2) = middle
            result(3) = nameParts(countParts - 1)
    End Select

OutputResult:
    ' If returnWord is specified, return only the requested word
    Select Case returnWord
        Case 1: FumaSplitName = result(1) ' First name
        Case 2: FumaSplitName = result(2) ' Middle name(s)
        Case 3: FumaSplitName = result(3) ' Last name
        Case Else: FumaSplitName = result ' Default: return all three parts
    End Select
End Function
