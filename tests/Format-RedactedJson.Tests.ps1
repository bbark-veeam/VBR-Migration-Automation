# Format-RedactedJson.Tests.ps1
# Unit tests for the private Format-RedactedJson helper. Pure function with no
# external dependencies — dot-sourced directly so the tests run without the
# module having to be loaded.
#
# Why this is tested: regressions here would leak credentials, tokens, and
# cloud secret keys into console output, logs, and PowerShell transcripts.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Format-RedactedJson.ps1')
}

Describe 'Format-RedactedJson' {
    Context 'sensitive keys are redacted' {
        It 'redacts <key>' -ForEach @(
            @{ Key = 'password'      }
            @{ Key = 'secretKey'     }
            @{ Key = 'sharedKey'     }
            @{ Key = 'bearer'        }
            @{ Key = 'apiKey'        }
            @{ Key = 'access_token'  }
            @{ Key = 'refreshToken'  }
        ) {
            $marker = "leaked_value_for_$Key"
            $input  = "{`"$Key`":`"$marker`"}"
            $result = Format-RedactedJson -Text $input

            $result | Should -Not -Match $marker -Because "$Key value must not appear in output"
            $result | Should -Match '"\*\*\*REDACTED\*\*\*"'
        }
    }

    Context 'case-insensitive matching' {
        It 'redacts <_> regardless of case' -ForEach @(
            'PASSWORD'
            'Password'
            'pAsSwOrD'
            'SECRETKEY'
            'ApiKey'
        ) {
            $input  = "{`"$_`":`"sensitive_data_here`"}"
            $result = Format-RedactedJson -Text $input
            $result | Should -Not -Match 'sensitive_data_here'
        }
    }

    Context 'non-sensitive fields are preserved' {
        It 'preserves name, port, and other innocuous fields' {
            $input = '{"name":"prod-repo","port":9419,"password":"x","description":"main bucket"}'
            $result = Format-RedactedJson -Text $input

            $result | Should -Match '"name"\s*:\s*"prod-repo"'
            $result | Should -Match '"port"\s*:\s*9419'
            $result | Should -Match '"description"\s*:\s*"main bucket"'
            $result | Should -Not -Match '"password"\s*:\s*"x"'
        }

        It 'preserves field names that merely contain sensitive substrings' {
            # 'passwordHint' contains 'password' but is not in the sensitive list.
            # The regex anchors on full quoted key names, so it should be left alone.
            $input  = '{"passwordHint":"first pet name"}'
            $result = Format-RedactedJson -Text $input
            $result | Should -Be $input
        }
    }

    Context 'idempotency' {
        It 'applying twice produces the same output' {
            $input = '{"username":"admin","password":"abc","apiKey":"xyz"}'
            $once  = Format-RedactedJson -Text $input
            $twice = Format-RedactedJson -Text $once
            $twice | Should -Be $once
        }

        It 'leaves already-redacted text unchanged' {
            $input  = '{"password":"***REDACTED***"}'
            $result = Format-RedactedJson -Text $input
            $result | Should -Be $input
        }
    }

    Context 'edge cases' {
        It 'returns empty string for empty input' {
            Format-RedactedJson -Text '' | Should -Be ''
        }

        It 'returns null for null input' {
            Format-RedactedJson -Text $null | Should -BeNullOrEmpty
        }

        It 'returns input unchanged when no sensitive keys are present' {
            $input = '{"name":"x","count":5,"enabled":true}'
            Format-RedactedJson -Text $input | Should -Be $input
        }

        It 'handles non-JSON text without errors' {
            $input  = 'Plain error message: connection refused on port 9419.'
            $result = Format-RedactedJson -Text $input
            $result | Should -Be $input
        }

        It 'handles escaped quotes inside the value' {
            # Value contains \" — the regex must match the full escaped value, not stop early.
            $input  = '{"password":"abc\"def"}'
            $result = Format-RedactedJson -Text $input

            $result | Should -Match '"\*\*\*REDACTED\*\*\*"'
            $result | Should -Not -Match 'abc'
            $result | Should -Not -Match 'def'
        }

        It 'redacts multiple sensitive keys in one payload' {
            $input  = '{"password":"p1","secretKey":"s1","apiKey":"a1","name":"keep_me"}'
            $result = Format-RedactedJson -Text $input

            $result | Should -Not -Match 'p1'
            $result | Should -Not -Match 's1'
            $result | Should -Not -Match 'a1'
            $result | Should -Match 'keep_me'
        }

        It 'redacts the same key appearing multiple times' {
            $input  = '{"items":[{"password":"x"},{"password":"y"}]}'
            $result = Format-RedactedJson -Text $input

            $result | Should -Not -Match '"password"\s*:\s*"x"'
            $result | Should -Not -Match '"password"\s*:\s*"y"'
            ($result | Select-String -Pattern '\*\*\*REDACTED\*\*\*' -AllMatches).Matches.Count |
                Should -Be 2
        }
    }

    Context 'whitespace tolerance' {
        It 'handles spaces around the colon' {
            $input  = '{"password" : "secret"}'
            $result = Format-RedactedJson -Text $input
            $result | Should -Not -Match 'secret'
        }

        It 'handles no spaces around the colon' {
            $input  = '{"password":"secret"}'
            $result = Format-RedactedJson -Text $input
            $result | Should -Not -Match 'secret'
        }
    }
}
