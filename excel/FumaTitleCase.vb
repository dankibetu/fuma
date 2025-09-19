Public Function FumaTitleCase(ByVal s As String) As String
    Dim i As Long
    Dim result As String
    Dim lowerS As String
    
    ' Convert the entire string to lower case
    lowerS = LCase(s)
    
    ' Capitalize the first character unconditionally
    result = UCase(Left(lowerS, 1))
    
    ' Loop through the rest of the characters
    For i = 2 To Len(lowerS)
        Dim currentChar As String
        currentChar = Mid(lowerS, i, 1)
        
        ' Capitalize if the preceding character is a space
        If Mid(lowerS, i - 1, 1) = " " Then
            result = result & UCase(currentChar)
        Else
            result = result & currentChar
        End If
    Next i
    
    FumaTitleCase = result
End Function

