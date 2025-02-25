Public Function FumaSplitName(fullName As String) As Variant
    Dim nameParts() As String
    Dim countParts As Integer
    Dim result(1 To 3) As String
    Dim i As Integer
    Dim middle As String
    
    ' Replace commas and decimals with a space
    fullName = Replace(fullName, ",", " ")
    fullName = Replace(fullName, ".", " ")
    
    ' Remove extra spaces
    fullName = Application.WorksheetFunction.Trim(fullName)
    
    ' If the string is empty, return three empty strings
    If fullName = "" Then
        result(1) = ""
        result(2) = ""
        result(3) = ""
        FumaSplitName = result
        Exit Function
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
    
    FumaSplitName = result
End Function


