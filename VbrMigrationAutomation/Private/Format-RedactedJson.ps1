# Format-RedactedJson
# Scrubs sensitive JSON field values from a string before it is logged or
# thrown. Replaces the values of keys like "password", "secretKey", "sharedKey",
# "bearer", "apiKey", "access_token", and "refreshToken" with "***REDACTED***".
# Intended for wrapping error-response bodies before they reach console output,
# logs, or PowerShell transcripts.
#
# Idempotent: applying the function to already-redacted text returns the same string.

function Format-RedactedJson {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    # Field names whose JSON values should never appear in logs.
    $sensitiveKeys = @(
        'password'
        'secretKey'
        'sharedKey'
        'bearer'
        'apiKey'
        'access_token'
        'refreshToken'
    )

    foreach ($key in $sensitiveKeys) {
        # Matches:  "key" : "value-with-optional-escapes"
        #   (?i)            case-insensitive
        #   $1              the quoted key
        #   $2              the colon and surrounding whitespace
        #   $3              the value (handles escaped quotes via [^"\\]|\\.)
        $pattern     = '(?i)("' + [regex]::Escape($key) + '")(\s*:\s*)"((?:[^"\\]|\\.)*)"'
        $replacement = '$1$2"***REDACTED***"'
        $Text        = $Text -replace $pattern, $replacement
    }

    return $Text
}
