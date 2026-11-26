function _aerospork_62
    set 1 $argv[1]
    true
end

function _aerospork_24
    set 1 $argv[1]
    aerospork list-apps --format '%{app-bundle-id}%{tab}%{app-name}'
end

function _aerospork_26
    set 1 $argv[1]
    aerospork list-apps --format '%{app-pid}%{tab}%{app-name}'
end

function _aerospork_20
    set 1 $argv[1]
    aerospork config --get mode --keys | xargs -I{} aerospork config --get mode.{}.binding --keys
end

function _aerospork_21
    set 1 $argv[1]
    aerospork config --get mode --keys
end

function _aerospork_61
    set 1 $argv[1]
    aerospork list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
end

function _aerospork_52
    set 1 $argv[1]
    aerospork list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
end

function _aerospork_53
    set 1 $argv[1]
    aerospork list-workspaces --all
end

function _aerospork_2
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

    set --local literals "move-mouse" "--count" "-v" "smart" "macos-native-fullscreen" "mute-toggle" "height" "toggle" "all-monitors-outer-frame" "h_accordion" "all" "--window-id" "monitor-force-center" "list-apps" "flatten-workspace-tree" "mode" "width" "summon-workspace" "focus-back-and-forth" "list-monitors" "h_tiles" "prev" "window-force-center" "trigger-binding" "-h" "move-node-to-workspace" "wrap-around-the-workspace" "enable" "--ignore-floating" "--visible" "close-all-windows-but-current" "--help" "--macos-native-hidden" "off" "move-workspace-to-monitor" "--boundaries" "set" "workspace-back-and-forth" "--quit-if-last-window" "window-lazy-center" "workspace" "--major-keys" "accordion" "--focused" "tiling" "--app-bundle-id" "--mouse" "balance-sizes" "opposite" "on" "--auto-back-and-forth" "--version" "--json" "join-with" "reload-config" "--workspace" "floating" "--swap-focus" "--mode" "--boundaries-action" "resize" "visible" "close" "up" "layout" "--fail-if-noop" "--tree" "fail" "list-exec-env-vars" "--focus-follows-window" "split" "--monitor" "--pid" "mute-on" "v_tiles" "monitor-lazy-center" "--keys" "wrap-around-all-monitors" "--wrap-around" "horizontal" "create-implicit-container" "config" "--no-outer-gaps" "focused" "mute-off" "--all-keys" "--show-secrets" "--all" "left" "right" "swap" "--config-path" "--get" "--empty" "tiles" "--no-gui" "dfs-next" "smart-opposite" "--format" "list-modes" "--dry-run" "move-node-to-monitor" "dfs-prev" "move" "focus" "down" "list-workspaces" "volume" "no" "stop" "debug-windows" "macos-native-minimize" "list-windows" "mouse" "next" "--dfs-index" "open-settings" "fullscreen" "focus-monitor" "--current" "v_accordion" "vertical"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 3 54 55 35 5 38 61 91 63 100 14 41 65 69 15 102 71 20 16 19 104 105 18 24 25 107 26 108 111 112 113 28 48 82 117 31 52 118 32 119; set tos 120 16 125 126 127 69 16 94 82 73 128 96 113 129 130 2 108 11 83 131 16 19 132 122 54 16 105 133 134 104 12 135 136 2 86 16 87 16 88 16 20"
    set literal_transitions[2] "set inputs 56; set tos 3"
    set literal_transitions[4] "set inputs 17 4 7 98; set tos 5 5 5 5"
    set literal_transitions[6] "set inputs 34 50; set tos 7 7"
    set literal_transitions[7] "set inputs 66; set tos 16"
    set literal_transitions[9] "set inputs 30 2 94 99 53; set tos 107 9 107 8 9"
    set literal_transitions[10] "set inputs 56; set tos 3"
    set literal_transitions[11] "set inputs 49 12 80 122; set tos 12 13 12 12"
    set literal_transitions[12] "set inputs 12; set tos 17"
    set literal_transitions[14] "set inputs 110 27 68 78; set tos 15 15 15 15"
    set literal_transitions[15] "set inputs 36 60 29; set tos 124 14 15"
    set literal_transitions[18] "set inputs 9 41; set tos 19 19"
    set literal_transitions[19] "set inputs 36 60 89 90 12 106 64; set tos 18 77 45 45 78 45 45"
    set literal_transitions[20] "set inputs 115 106 22 64 89 90 79; set tos 22 22 22 22 22 22 23"
    set literal_transitions[22] "set inputs 79; set tos 16"
    set literal_transitions[23] "set inputs 89 90 115 106 22 64; set tos 22 22 22 22 22 22"
    set literal_transitions[25] "set inputs 53 77; set tos 25 25"
    set literal_transitions[26] "set inputs 11 2 73 114 56 99 72 46 53 84; set tos 26 27 28 26 29 30 32 31 27 26"
    set literal_transitions[27] "set inputs 73 2 46 56 53 72 99; set tos 28 27 31 29 27 32 30"
    set literal_transitions[29] "set inputs 84 62; set tos 34 34"
    set literal_transitions[32] "set inputs 11 114 84; set tos 26 26 26"
    set literal_transitions[33] "set inputs 53 93 77; set tos 33 24 33"
    set literal_transitions[34] "set inputs 73 2 62 56 99 46 53 84 72; set tos 28 27 34 29 30 31 27 34 32"
    set literal_transitions[35] "set inputs 79 70; set tos 35 35"
    set literal_transitions[36] "set inputs 10 21 57 80 95 45 75 43 121 122; set tos 37 37 37 37 37 37 37 37 37 37"
    set literal_transitions[37] "set inputs 10 21 57 80 95 45 75 43 121 122; set tos 37 37 37 37 37 37 37 37 37 37"
    set literal_transitions[38] "set inputs 83 66 12 34 50; set tos 39 39 40 41 42"
    set literal_transitions[39] "set inputs 83 66 12 50; set tos 39 39 40 42"
    set literal_transitions[41] "set inputs 12 66; set tos 17 16"
    set literal_transitions[42] "set inputs 12 83 66; set tos 93 42 42"
    set literal_transitions[43] "set inputs 51 66; set tos 43 43"
    set literal_transitions[44] "set inputs 68 81 110; set tos 45 45 45"
    set literal_transitions[45] "set inputs 12 36 60; set tos 52 53 44"
    set literal_transitions[46] "set inputs 66 12 70; set tos 47 48 47"
    set literal_transitions[47] "set inputs 12 66 70; set tos 48 47 47"
    set literal_transitions[50] "set inputs 115 12 22 106 64 89 90 79 70; set tos 91 49 91 91 91 91 91 50 50"
    set literal_transitions[51] "set inputs 115 22 79 70; set tos 35 35 51 51"
    set literal_transitions[53] "set inputs 9 41; set tos 45 45"
    set literal_transitions[54] "set inputs 59; set tos 56"
    set literal_transitions[55] "set inputs 59; set tos 131"
    set literal_transitions[57] "set inputs 110 27 68 78; set tos 58 58 58 58"
    set literal_transitions[58] "set inputs 36 60 89 90 106 29 64; set tos 143 57 15 15 15 58 15"
    set literal_transitions[59] "set inputs 30 2 94 99 53 72; set tos 60 59 60 61 59 62"
    set literal_transitions[60] "set inputs 30 2 109 94 99 53 72; set tos 60 59 59 60 61 59 62"
    set literal_transitions[62] "set inputs 11 114 84; set tos 106 106 106"
    set literal_transitions[63] "set inputs 66 12 70; set tos 63 64 63"
    set literal_transitions[66] "set inputs 12 66; set tos 65 66"
    set literal_transitions[67] "set inputs 66 12 34 50; set tos 67 68 66 66"
    set literal_transitions[69] "set inputs 66 12 34 50; set tos 67 70 66 66"
    set literal_transitions[71] "set inputs 66 12 70; set tos 71 72 71"
    set literal_transitions[73] "set inputs 12 39; set tos 74 73"
    set literal_transitions[76] "set inputs 2 94 99 44 30 88 53 72; set tos 59 60 61 103 60 103 59 62"
    set literal_transitions[77] "set inputs 68 81 110; set tos 19 19 19"
    set literal_transitions[79] "set inputs 12 58 79; set tos 80 79 79"
    set literal_transitions[82] "set inputs 106 12 97 58 64 89 90 79 103; set tos 79 81 79 82 79 79 79 82 79"
    set literal_transitions[83] "set inputs 2 99 53 47 44; set tos 83 84 83 85 85"
    set literal_transitions[85] "set inputs 109 2 99 53 47 44; set tos 83 83 84 83 85 85"
    set literal_transitions[86] "set inputs 86 42 77 53 93 92; set tos 16 16 33 33 24 16"
    set literal_transitions[87] "set inputs 39; set tos 16"
    set literal_transitions[88] "set inputs 83 66 12 34 50; set tos 89 38 90 41 42"
    set literal_transitions[89] "set inputs 83 66 12 50; set tos 89 39 100 42"
    set literal_transitions[91] "set inputs 12 79 70; set tos 92 91 91"
    set literal_transitions[94] "set inputs 17 4 7 12 98; set tos 5 5 5 95 5"
    set literal_transitions[96] "set inputs 2 99 53 33; set tos 96 97 96 98"
    set literal_transitions[98] "set inputs 109 2 99 53 33; set tos 96 96 97 96 98"
    set literal_transitions[99] "set inputs 83 66 12 34 50; set tos 89 39 100 41 42"
    set literal_transitions[102] "set inputs 73 2 56 99 44 88 46 53 72; set tos 28 27 29 30 103 103 31 27 32"
    set literal_transitions[103] "set inputs 99 2 53; set tos 138 16 16"
    set literal_transitions[104] "set inputs 12 67; set tos 17 16"
    set literal_transitions[105] "set inputs 2 94 99 44 30 88 53 72; set tos 76 60 75 103 60 103 76 62"
    set literal_transitions[106] "set inputs 11 2 114 94 99 30 53 84; set tos 106 9 106 107 8 107 9 106"
    set literal_transitions[107] "set inputs 30 2 109 94 99 53; set tos 107 9 9 107 8 9"
    set literal_transitions[108] "set inputs 115 12 22 106 64 89 90 66 79 70; set tos 91 109 91 91 91 91 91 71 50 108"
    set literal_transitions[110] "set inputs 56 79; set tos 111 110"
    set literal_transitions[112] "set inputs 80 122 49; set tos 12 12 12"
    set literal_transitions[113] "set inputs 51 66 115 22 79; set tos 114 114 22 22 115"
    set literal_transitions[114] "set inputs 51 66; set tos 114 114"
    set literal_transitions[115] "set inputs 22 115; set tos 22 22"
    set literal_transitions[117] "set inputs 115 56 22 106 64 89 90 79; set tos 110 118 110 110 110 110 110 119"
    set literal_transitions[119] "set inputs 115 106 56 22 64 89 90 79; set tos 110 110 118 110 110 110 110 119"
    set literal_transitions[120] "set inputs 66 40 13 23 76; set tos 121 7 7 7 7"
    set literal_transitions[121] "set inputs 76 40 13 23; set tos 7 7 7 7"
    set literal_transitions[122] "set inputs 66; set tos 123"
    set literal_transitions[124] "set inputs 9 41; set tos 15 15"
    set literal_transitions[125] "set inputs 89 90 12 106 64; set tos 16 16 139 16 16"
    set literal_transitions[126] "set inputs 96 101; set tos 126 126"
    set literal_transitions[127] "set inputs 115 56 22 106 64 89 90 79; set tos 110 116 110 110 110 110 110 119"
    set literal_transitions[128] "set inputs 120; set tos 16"
    set literal_transitions[129] "set inputs 10 95 12 21 57 80 45 75 43 121 122; set tos 37 37 137 37 37 37 37 37 37 37 37"
    set literal_transitions[130] "set inputs 87; set tos 16"
    set literal_transitions[132] "set inputs 12 106 29 64 36 60 89 90 116; set tos 17 15 58 15 143 57 15 15 138"
    set literal_transitions[133] "set inputs 70 66 115 12 79 22; set tos 133 63 35 64 51 35"
    set literal_transitions[134] "set inputs 64 37 6 74 106 85; set tos 16 138 16 16 16 16"
    set literal_transitions[135] "set inputs 73 2 56 99 44 88 46 53 72; set tos 28 102 29 141 103 103 31 102 32"
    set literal_transitions[136] "set inputs 66 34 8 50; set tos 6 7 16 7"
    set literal_transitions[140] "set inputs 89 90 106 64; set tos 16 16 16 16"
    set literal_transitions[142] "set inputs 66 12 34 50; set tos 67 68 66 66"
    set literal_transitions[143] "set inputs 9 41; set tos 58 58"

    set --local match_anything_transitions_from 54 24 40 48 34 131 127 122 123 80 133 46 106 21 29 10 65 20 68 101 56 63 114 31 111 28 108 139 118 64 70 26 109 95 3 61 138 137 117 116 97 92 72 49 52 71 93 100 81 62 84 32 113 30 75 74 90 8 78 13 17 141
    set --local match_anything_transitions_to 55 25 39 47 34 16 10 7 7 79 47 46 106 21 34 10 66 21 67 16 101 47 43 27 110 27 46 140 119 63 142 26 108 4 16 59 16 36 10 117 96 91 71 50 45 46 42 89 82 106 83 26 43 27 76 73 99 9 19 112 16 102
    set subword_transitions[5] "set subword_ids 1; set tos 12"

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

    set command_states 54 64 70 26 24 40 109 95 3 48 34 61 138 137 117 131 127 122 116 97 123 72 80 92 133 49 52 71 46 106 93 100 21 62 29 81 84 32 10 113 30 75 74 90 8 65 78 20 68 101 56 63 114 13 31 111 108 28 17 139 118 141
    set command_ids 20 61 61 52 2 61 61 61 53 61 53 62 62 61 62 21 62 53 53 62 53 61 61 61 53 61 61 62 62 52 61 61 62 52 53 61 62 52 62 53 62 62 61 61 62 61 61 62 61 20 21 53 53 61 24 53 62 26 61 61 53 62
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
