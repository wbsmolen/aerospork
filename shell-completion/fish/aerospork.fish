function _aerospork_57
    set 1 $argv[1]
    true
end

function _aerospork_41
    set 1 $argv[1]
    aerospork list-apps --format '%{app-bundle-id}%{tab}%{app-name}'
end

function _aerospork_59
    set 1 $argv[1]
    aerospork list-apps --format '%{app-pid}%{tab}%{app-name}'
end

function _aerospork_32
    set 1 $argv[1]
    aerospork config --get mode --keys | xargs -I{} aerospork config --get mode.{}.binding --keys
end

function _aerospork_60
    set 1 $argv[1]
    aerospork config --get mode --keys
end

function _aerospork_55
    set 1 $argv[1]
    aerospork list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
end

function _aerospork_56
    set 1 $argv[1]
    aerospork list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
end

function _aerospork_58
    set 1 $argv[1]
    aerospork list-workspaces --all
end

function _aerospork_44
    set 1 $argv[1]
    aerospork config --major-keys
end

function _aerospork_subword_cmd_0
    true
end

function _aerospork_subword_1
    set mode $argv[1]
    set word $argv[2]

    set --local literals "-" "+"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 2; set tos 2 2"

    set --local match_anything_transitions_from 1 2
    set --local match_anything_transitions_to 3 3

    set --local state 1
    set --local char_index 1
    set --local matched 0
    while true
        if test $char_index -gt (string length -- "$word")
            set matched 1
            break
        end

        set --local subword (string sub --start=$char_index -- "$word")

        if set --query literal_transitions[$state] && test -n $literal_transitions[$state]
            set --local --erase inputs
            set --local --erase tos
            eval $literal_transitions[$state]

            set --local literal_matched 0
            for literal_id in (seq 1 (count $literals))
                set --local literal $literals[$literal_id]
                set --local literal_len (string length -- "$literal")
                set --local subword_slice (string sub --end=$literal_len -- "$subword")
                if test $subword_slice = $literal
                    set --local index (contains --index -- $literal_id $inputs)
                    set state $tos[$index]
                    set char_index (math $char_index + $literal_len)
                    set literal_matched 1
                    break
                end
            end
            if test $literal_matched -ne 0
                continue
            end
        end

        if set --query match_anything_transitions_from[$state] && test -n $match_anything_transitions_from[$state]
            set --local index (contains --index -- $state $match_anything_transitions_from)
            set state $match_anything_transitions_to[$index]
            set --local matched 1
            break
        end

        break
    end

    if test $mode = matches
        return (math 1 - $matched)
    end


    set --local unmatched_suffix (string sub --start=$char_index -- $word)

    set --local matched_prefix
    if test $char_index -eq 1
        set matched_prefix ""
    else
        set matched_prefix (string sub --end=(math $char_index - 1) -- "$word")
    end
    if set --query literal_transitions[$state] && test -n $literal_transitions[$state]
        set --local --erase inputs
        set --local --erase tos
        eval $literal_transitions[$state]
        for literal_id in $inputs
            set --local unmatched_suffix_len (string length -- $unmatched_suffix)
            if test $unmatched_suffix_len -gt 0
                set --local literal $literals[$literal_id]
                set --local slice (string sub --end=$unmatched_suffix_len -- $literal)
                if test "$slice" != "$unmatched_suffix"
                    continue
                end
            end
            if test -n $descriptions[$literal_id]
                printf '%s%s\t%s\n' $matched_prefix $literals[$literal_id] $descriptions[$literal_id]
            else
                printf '%s%s\n' $matched_prefix $literals[$literal_id]
            end
        end
    end

    set command_states 1 2
    set command_ids 0 0
    if contains $state $command_states
        set --local index (contains --index $state $command_states)
        set --local function_id $command_ids[$index]
        set --local function_name _aerospork_subword_cmd_$function_id
        set --local --erase inputs
        set --local --erase tos
        $function_name "$matched_prefix" | while read --local line
            printf '%s%s\n' $matched_prefix $line
        end
    end

    return 0
end


function _aerospork
    set COMP_LINE (commandline --cut-at-cursor)

    set COMP_WORDS
    echo $COMP_LINE | read --tokenize --array COMP_WORDS
    if string match --quiet --regex '.*\s$' $COMP_LINE
        set COMP_CWORD (math (count $COMP_WORDS) + 1)
    else
        set COMP_CWORD (count $COMP_WORDS)
    end

    set --local literals "move-mouse" "--count" "-v" "smart" "macos-native-fullscreen" "mute-toggle" "height" "toggle" "all-monitors-outer-frame" "h_accordion" "all" "--window-id" "monitor-force-center" "list-apps" "flatten-workspace-tree" "mode" "width" "summon-workspace" "focus-back-and-forth" "list-monitors" "h_tiles" "prev" "window-force-center" "trigger-binding" "-h" "move-node-to-workspace" "wrap-around-the-workspace" "enable" "--ignore-floating" "--visible" "close-all-windows-but-current" "--help" "--macos-native-hidden" "off" "move-workspace-to-monitor" "--boundaries" "set" "workspace-back-and-forth" "--quit-if-last-window" "window-lazy-center" "workspace" "--major-keys" "accordion" "--focused" "tiling" "--app-bundle-id" "--mouse" "balance-sizes" "opposite" "on" "--auto-back-and-forth" "--version" "--json" "join-with" "reload-config" "--workspace" "floating" "--mode" "--boundaries-action" "resize" "visible" "close" "up" "layout" "--fail-if-noop" "--tree" "fail" "list-exec-env-vars" "--focus-follows-window" "split" "--monitor" "--pid" "mute-on" "v_tiles" "monitor-lazy-center" "--keys" "wrap-around-all-monitors" "--wrap-around" "horizontal" "create-implicit-container" "config" "--no-outer-gaps" "focused" "mute-off" "--all-keys" "--show-secrets" "--all" "left" "right" "--config-path" "--get" "--empty" "tiles" "--no-gui" "--format" "smart-opposite" "list-modes" "--dry-run" "move-node-to-monitor" "move" "focus" "down" "list-workspaces" "volume" "no" "stop" "debug-windows" "macos-native-minimize" "list-windows" "mouse" "next" "--dfs-index" "open-settings" "fullscreen" "focus-monitor" "--current" "v_accordion" "vertical"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 3 54 55 35 5 38 60 62 97 14 41 64 68 15 99 70 20 16 19 100 101 18 24 25 103 26 104 107 108 109 28 48 81 113 31 52 114 32 115; set tos 113 24 119 120 121 62 24 89 45 110 94 107 122 123 2 124 8 55 115 24 59 68 116 48 24 125 126 100 127 9 16 128 2 79 24 82 24 129 24 83"
    set literal_transitions[2] "set inputs 56; set tos 3"
    set literal_transitions[4] "set inputs 10 21 57 79 93 45 74 43 117 118; set tos 5 5 5 5 5 5 5 5 5 5"
    set literal_transitions[5] "set inputs 10 21 57 79 93 45 74 43 117 118; set tos 5 5 5 5 5 5 5 5 5 5"
    set literal_transitions[7] "set inputs 88 89 102 63; set tos 24 24 24 24"
    set literal_transitions[8] "set inputs 49 12 79 118; set tos 9 10 9 9"
    set literal_transitions[9] "set inputs 12; set tos 69"
    set literal_transitions[11] "set inputs 22 111; set tos 12 12"
    set literal_transitions[12] "set inputs 78; set tos 24"
    set literal_transitions[13] "set inputs 65 12 69; set tos 13 14 13"
    set literal_transitions[15] "set inputs 12 65 69; set tos 46 15 15"
    set literal_transitions[16] "set inputs 72 2 56 95 44 87 46 53 71; set tos 17 18 19 20 21 21 22 18 23"
    set literal_transitions[18] "set inputs 72 2 56 95 44 87 46 53 71; set tos 17 87 19 88 21 21 22 87 23"
    set literal_transitions[19] "set inputs 83 61; set tos 98 98"
    set literal_transitions[21] "set inputs 95 2 53; set tos 57 24 24"
    set literal_transitions[23] "set inputs 11 110 83; set tos 109 109 109"
    set literal_transitions[25] "set inputs 82 65 12 50; set tos 25 25 26 27"
    set literal_transitions[27] "set inputs 12 82 65; set tos 30 27 27"
    set literal_transitions[29] "set inputs 82 65 12 50; set tos 29 25 28 27"
    set literal_transitions[31] "set inputs 111 102 56 22 63 88 89 78; set tos 32 32 33 32 32 32 32 31"
    set literal_transitions[32] "set inputs 56 78; set tos 114 32"
    set literal_transitions[34] "set inputs 12 36 59; set tos 35 36 37"
    set literal_transitions[36] "set inputs 9 41; set tos 34 34"
    set literal_transitions[37] "set inputs 67 80 106; set tos 34 34 34"
    set literal_transitions[39] "set inputs 30 2 92 95 53 71; set tos 135 39 135 38 39 112"
    set literal_transitions[40] "set inputs 82 65 12 34 50; set tos 25 25 26 41 27"
    set literal_transitions[41] "set inputs 12 65; set tos 69 24"
    set literal_transitions[43] "set inputs 12 78 69; set tos 42 43 43"
    set literal_transitions[45] "set inputs 12 39; set tos 44 45"
    set literal_transitions[48] "set inputs 58; set tos 50"
    set literal_transitions[49] "set inputs 58; set tos 115"
    set literal_transitions[51] "set inputs 106 27 67 77; set tos 52 52 52 52"
    set literal_transitions[52] "set inputs 36 59 29; set tos 106 51 52"
    set literal_transitions[53] "set inputs 78 69; set tos 53 53"
    set literal_transitions[54] "set inputs 105 2 95 53 47 44; set tos 55 55 56 55 54 54"
    set literal_transitions[55] "set inputs 2 95 53 47 44; set tos 55 56 55 54 54"
    set literal_transitions[58] "set inputs 9 41; set tos 59 59"
    set literal_transitions[59] "set inputs 36 59 88 89 12 102 63; set tos 58 102 34 34 60 34 34"
    set literal_transitions[62] "set inputs 65 12 34 50; set tos 63 64 65 65"
    set literal_transitions[63] "set inputs 65 12 34 50; set tos 63 74 65 65"
    set literal_transitions[65] "set inputs 12 65; set tos 75 65"
    set literal_transitions[67] "set inputs 30 2 92 95 53; set tos 93 67 93 66 67"
    set literal_transitions[68] "set inputs 12 102 29 63 36 59 88 89 112; set tos 69 52 70 52 71 72 52 52 57"
    set literal_transitions[70] "set inputs 36 59 88 89 102 29 63; set tos 71 72 52 52 52 70 52"
    set literal_transitions[71] "set inputs 9 41; set tos 70 70"
    set literal_transitions[72] "set inputs 106 27 67 77; set tos 70 70 70 70"
    set literal_transitions[73] "set inputs 65 12 34 50; set tos 63 74 65 65"
    set literal_transitions[76] "set inputs 75 40 13 23; set tos 77 77 77 77"
    set literal_transitions[77] "set inputs 65; set tos 24"
    set literal_transitions[78] "set inputs 56; set tos 3"
    set literal_transitions[79] "set inputs 85 42 76 53 91 90; set tos 24 24 80 80 81 24"
    set literal_transitions[80] "set inputs 53 91 76; set tos 80 81 80"
    set literal_transitions[82] "set inputs 39; set tos 24"
    set literal_transitions[83] "set inputs 111 102 22 63 88 89 78; set tos 12 12 12 12 12 12 84"
    set literal_transitions[84] "set inputs 88 89 111 102 22 63; set tos 12 12 12 12 12 12"
    set literal_transitions[86] "set inputs 65 12 69; set tos 86 85 86"
    set literal_transitions[87] "set inputs 72 2 46 56 53 71 95; set tos 17 87 22 19 87 23 88"
    set literal_transitions[89] "set inputs 17 4 7 12 96; set tos 90 90 90 91 90"
    set literal_transitions[92] "set inputs 11 2 110 92 95 30 53 83; set tos 92 67 92 93 66 93 67 92"
    set literal_transitions[93] "set inputs 30 2 105 92 95 53; set tos 93 67 67 93 66 67"
    set literal_transitions[94] "set inputs 2 95 53 33; set tos 94 95 94 96"
    set literal_transitions[96] "set inputs 105 2 95 53 33; set tos 94 94 95 94 96"
    set literal_transitions[97] "set inputs 111 56 22 102 63 88 89 78; set tos 32 33 32 32 32 32 32 31"
    set literal_transitions[98] "set inputs 72 2 61 56 95 46 53 83 71; set tos 17 87 98 19 88 22 87 98 23"
    set literal_transitions[99] "set inputs 53 76; set tos 99 99"
    set literal_transitions[100] "set inputs 63 37 6 73 102 84; set tos 24 57 24 24 24 24"
    set literal_transitions[101] "set inputs 79 118 49; set tos 9 9 9"
    set literal_transitions[102] "set inputs 67 80 106; set tos 59 59 59"
    set literal_transitions[103] "set inputs 51 65; set tos 103 103"
    set literal_transitions[105] "set inputs 111 12 22 102 63 88 89 78 69; set tos 43 104 43 43 43 43 43 105 105"
    set literal_transitions[106] "set inputs 9 41; set tos 52 52"
    set literal_transitions[107] "set inputs 51 65 111 22 78; set tos 108 108 12 12 11"
    set literal_transitions[108] "set inputs 51 65; set tos 108 108"
    set literal_transitions[109] "set inputs 11 2 72 110 56 95 71 46 53 83; set tos 109 87 17 109 19 88 23 22 87 109"
    set literal_transitions[110] "set inputs 116; set tos 24"
    set literal_transitions[111] "set inputs 17 4 7 96; set tos 90 90 90 90"
    set literal_transitions[112] "set inputs 11 110 83; set tos 92 92 92"
    set literal_transitions[113] "set inputs 65 40 13 23 75; set tos 76 77 77 77 77"
    set literal_transitions[116] "set inputs 65; set tos 117"
    set literal_transitions[118] "set inputs 65 12 69; set tos 15 46 15"
    set literal_transitions[119] "set inputs 88 89 12 102 63; set tos 24 24 6 24 24"
    set literal_transitions[120] "set inputs 94 98; set tos 120 120"
    set literal_transitions[121] "set inputs 111 56 22 102 63 88 89 78; set tos 32 133 32 32 32 32 32 31"
    set literal_transitions[122] "set inputs 10 93 12 21 57 79 45 74 43 117 118; set tos 5 5 134 5 5 5 5 5 5 5 5"
    set literal_transitions[123] "set inputs 86; set tos 24"
    set literal_transitions[124] "set inputs 111 12 22 102 63 88 89 65 78 69; set tos 43 137 43 43 43 43 43 86 105 124"
    set literal_transitions[125] "set inputs 2 92 95 44 30 87 53 71; set tos 131 135 130 21 135 21 131 112"
    set literal_transitions[126] "set inputs 69 65 111 12 78 22; set tos 126 13 53 14 136 53"
    set literal_transitions[127] "set inputs 12 66; set tos 69 24"
    set literal_transitions[128] "set inputs 65 34 8 50; set tos 139 77 24 77"
    set literal_transitions[129] "set inputs 82 65 12 34 50; set tos 29 40 138 41 27"
    set literal_transitions[131] "set inputs 2 92 95 44 30 87 53 71; set tos 39 135 38 21 135 21 39 112"
    set literal_transitions[132] "set inputs 82 65 12 34 50; set tos 29 25 28 41 27"
    set literal_transitions[135] "set inputs 30 2 105 92 95 53 71; set tos 135 39 39 135 38 39 112"
    set literal_transitions[136] "set inputs 111 22 78 69; set tos 53 53 136 136"
    set literal_transitions[139] "set inputs 34 50; set tos 77 77"

    set --local match_anything_transitions_from 112 48 44 66 88 47 133 46 83 85 86 10 14 60 6 20 56 114 33 108 28 69 118 38 64 26 50 109 95 3 124 61 138 137 117 116 97 126 91 42 22 92 130 81 19 104 107 98 121 30 75 74 134 78 35 23 57 13 17 115
    set --local match_anything_transitions_to 92 49 45 67 87 47 97 15 47 86 118 101 13 59 7 18 55 32 31 103 29 24 118 39 73 25 61 109 94 24 118 24 132 124 77 77 78 15 111 43 87 92 131 99 98 105 103 98 78 27 65 63 4 78 34 109 24 15 87 24
    set subword_transitions[90] "set subword_ids 1; set tos 9"

    set --local state 1
    set --local word_index 2
    while test $word_index -lt $COMP_CWORD
        set --local -- word $COMP_WORDS[$word_index]

        if set --query literal_transitions[$state] && test -n $literal_transitions[$state]
            set --local --erase inputs
            set --local --erase tos
            eval $literal_transitions[$state]

            if contains -- $word $literals
                set --local literal_matched 0
                for literal_id in (seq 1 (count $literals))
                    if test $literals[$literal_id] = $word
                        set --local index (contains --index -- $literal_id $inputs)
                        set state $tos[$index]
                        set word_index (math $word_index + 1)
                        set literal_matched 1
                        break
                    end
                end
                if test $literal_matched -ne 0
                    continue
                end
            end
        end

        if set --query subword_transitions[$state] && test -n $subword_transitions[$state]
            set --local --erase subword_ids
            set --local --erase tos
            eval $subword_transitions[$state]

            set --local subword_matched 0
            for subword_id in $subword_ids
                if _aerospork_subword_$subword_id matches "$word"
                    set subword_matched 1
                    set state $tos[$subword_id]
                    set word_index (math $word_index + 1)
                    break
                end
            end
            if test $subword_matched -ne 0
                continue
            end
        end

        if set --query match_anything_transitions_from[$state] && test -n $match_anything_transitions_from[$state]
            set --local index (contains --index -- $state $match_anything_transitions_from)
            set state $match_anything_transitions_to[$index]
            set word_index (math $word_index + 1)
            continue
        end

        return 1
    end

    if set --query literal_transitions[$state] && test -n $literal_transitions[$state]
        set --local --erase inputs
        set --local --erase tos
        eval $literal_transitions[$state]
        for literal_id in $inputs
            if test -n $descriptions[$literal_id]
                printf '%s\t%s\n' $literals[$literal_id] $descriptions[$literal_id]
            else
                printf '%s\n' $literals[$literal_id]
            end
        end
    end


    if set --query subword_transitions[$state] && test -n $subword_transitions[$state]
        set --local --erase subword_ids
        set --local --erase tos
        eval $subword_transitions[$state]

        for subword_id in $subword_ids
            set --local function_name _aerospork_subword_$subword_id
            $function_name complete "$COMP_WORDS[$COMP_CWORD]"
        end
    end

    set command_states 64 112 26 50 109 95 3 48 124 61 138 137 117 116 44 97 126 66 91 88 42 47 22 92 133 46 83 85 86 130 104 81 19 107 10 98 121 30 14 75 74 134 78 60 35 6 20 23 57 56 13 114 33 108 28 69 17 118 38 115
    set command_ids 55 56 55 60 56 57 58 32 57 32 55 55 58 58 55 57 58 57 55 57 55 57 41 56 58 55 57 55 57 57 55 44 58 58 55 58 57 55 55 55 55 55 57 55 55 55 57 56 57 57 58 58 58 58 55 55 59 57 57 60
    if contains $state $command_states
        set --local index (contains --index $state $command_states)
        set --local function_id $command_ids[$index]
        set --local function_name _aerospork_$function_id
        set --local --erase inputs
        set --local --erase tos
        $function_name "$COMP_WORDS[$COMP_CWORD]"
    end

    return 0
end

complete --command aerospork --no-files --arguments "(_aerospork)"
