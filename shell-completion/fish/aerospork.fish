function _aerospork_57
    set 1 $argv[1]
    true
end

function _aerospork_19
    set 1 $argv[1]
    aerospork list-apps --format '%{app-bundle-id}%{tab}%{app-name}'
end

function _aerospork_20
    set 1 $argv[1]
    aerospork list-apps --format '%{app-pid}%{tab}%{app-name}'
end

function _aerospork_58
    set 1 $argv[1]
    aerospork config --get mode --keys | xargs -I{} aerospork config --get mode.{}.binding --keys
end

function _aerospork_44
    set 1 $argv[1]
    aerospork config --get mode --keys
end

function _aerospork_60
    set 1 $argv[1]
    aerospork list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
end

function _aerospork_39
    set 1 $argv[1]
    aerospork list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
end

function _aerospork_53
    set 1 $argv[1]
    aerospork list-workspaces --all
end

function _aerospork_6
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

    set --local literals "move-mouse" "--count" "-v" "smart" "macos-native-fullscreen" "mute-toggle" "height" "toggle" "all-monitors-outer-frame" "h_accordion" "all" "--window-id" "monitor-force-center" "list-apps" "flatten-workspace-tree" "mode" "width" "summon-workspace" "focus-back-and-forth" "list-monitors" "h_tiles" "prev" "window-force-center" "trigger-binding" "-h" "move-node-to-workspace" "wrap-around-the-workspace" "enable" "--ignore-floating" "--visible" "close-all-windows-but-current" "--help" "--macos-native-hidden" "off" "move-workspace-to-monitor" "--boundaries" "set" "workspace-back-and-forth" "--quit-if-last-window" "window-lazy-center" "workspace" "--major-keys" "accordion" "--focused" "tiling" "--app-bundle-id" "--mouse" "balance-sizes" "opposite" "on" "--auto-back-and-forth" "--version" "--json" "join-with" "reload-config" "--workspace" "floating" "--mode" "--boundaries-action" "resize" "visible" "close" "up" "layout" "--fail-if-noop" "list-exec-env-vars" "fail" "--monitor" "--focus-follows-window" "split" "--pid" "mute-on" "v_tiles" "monitor-lazy-center" "--keys" "wrap-around-all-monitors" "--wrap-around" "horizontal" "create-implicit-container" "config" "--no-outer-gaps" "focused" "mute-off" "--all-keys" "--show-secrets" "--all" "left" "right" "--config-path" "--get" "--empty" "tiles" "--no-gui" "--format" "smart-opposite" "list-modes" "--dry-run" "move-node-to-monitor" "move" "focus" "down" "list-workspaces" "volume" "no" "stop" "debug-windows" "macos-native-minimize" "list-windows" "mouse" "next" "--dfs-index" "open-settings" "fullscreen" "focus-monitor" "--current" "v_accordion" "vertical"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 3 54 55 35 5 38 60 62 96 14 41 64 66 15 98 70 20 16 19 99 100 18 24 25 102 26 103 106 107 108 28 48 80 112 31 52 113 32 114; set tos 115 43 121 122 123 71 43 92 28 113 93 108 124 125 4 126 15 47 114 43 69 75 119 57 43 127 128 100 16 16 19 129 4 85 43 86 43 130 43 87"
    set literal_transitions[2] "set inputs 11 109 82; set tos 3 3 3"
    set literal_transitions[3] "set inputs 11 2 109 91 94 30 53 82; set tos 3 39 3 40 41 40 39 3"
    set literal_transitions[4] "set inputs 56; set tos 5"
    set literal_transitions[6] "set inputs 56 77; set tos 7 6"
    set literal_transitions[9] "set inputs 12 77 69; set tos 8 9 9"
    set literal_transitions[10] "set inputs 81 65 12 34 50; set tos 11 11 12 13 14"
    set literal_transitions[11] "set inputs 81 65 12 50; set tos 11 11 12 14"
    set literal_transitions[13] "set inputs 12 65; set tos 76 43"
    set literal_transitions[14] "set inputs 12 81 65; set tos 53 14 14"
    set literal_transitions[15] "set inputs 49 12 78 117; set tos 16 17 16 16"
    set literal_transitions[16] "set inputs 12; set tos 76"
    set literal_transitions[18] "set inputs 77 69; set tos 18 18"
    set literal_transitions[19] "set inputs 71 2 56 94 44 86 46 53 68; set tos 20 21 22 23 24 24 25 21 26"
    set literal_transitions[21] "set inputs 71 2 56 94 44 86 46 53 68; set tos 20 32 22 33 24 24 25 32 26"
    set literal_transitions[22] "set inputs 82 61; set tos 31 31"
    set literal_transitions[24] "set inputs 94 2 53; set tos 56 43 43"
    set literal_transitions[26] "set inputs 11 109 82; set tos 109 109 109"
    set literal_transitions[28] "set inputs 12 39; set tos 27 28"
    set literal_transitions[30] "set inputs 81 65 12 34 50; set tos 131 11 132 13 14"
    set literal_transitions[31] "set inputs 71 2 61 56 94 46 53 82 68; set tos 20 32 31 22 33 25 32 31 26"
    set literal_transitions[32] "set inputs 71 2 46 56 53 68 94; set tos 20 32 25 22 32 26 33"
    set literal_transitions[35] "set inputs 10 21 57 78 92 45 73 43 116 117; set tos 51 51 51 51 51 51 51 51 51 51"
    set literal_transitions[36] "set inputs 53 90 75; set tos 36 37 36"
    set literal_transitions[38] "set inputs 51 65; set tos 38 38"
    set literal_transitions[39] "set inputs 30 2 91 94 53; set tos 40 39 40 41 39"
    set literal_transitions[40] "set inputs 30 2 104 91 94 53; set tos 40 39 39 40 41 39"
    set literal_transitions[42] "set inputs 87 88 101 63; set tos 43 43 43 43"
    set literal_transitions[44] "set inputs 9 41; set tos 45 45"
    set literal_transitions[45] "set inputs 12 36 59; set tos 66 44 67"
    set literal_transitions[47] "set inputs 2 94 53 47 44; set tos 47 46 47 84 84"
    set literal_transitions[48] "set inputs 65 12 34 50; set tos 48 49 50 50"
    set literal_transitions[50] "set inputs 12 65; set tos 117 50"
    set literal_transitions[51] "set inputs 10 21 57 78 92 45 73 43 116 117; set tos 51 51 51 51 51 51 51 51 51 51"
    set literal_transitions[55] "set inputs 65 12 69; set tos 55 54 55"
    set literal_transitions[57] "set inputs 58; set tos 59"
    set literal_transitions[58] "set inputs 58; set tos 114"
    set literal_transitions[60] "set inputs 105 27 67 76; set tos 61 61 61 61"
    set literal_transitions[61] "set inputs 36 59 29; set tos 107 60 61"
    set literal_transitions[62] "set inputs 22 110; set tos 63 63"
    set literal_transitions[63] "set inputs 77; set tos 43"
    set literal_transitions[65] "set inputs 12 65 69; set tos 64 65 65"
    set literal_transitions[67] "set inputs 67 79 105; set tos 45 45 45"
    set literal_transitions[68] "set inputs 67 79 105; set tos 69 69 69"
    set literal_transitions[69] "set inputs 36 59 87 88 12 101 63; set tos 101 68 45 45 70 45 45"
    set literal_transitions[71] "set inputs 65 12 34 50; set tos 48 72 50 50"
    set literal_transitions[74] "set inputs 110 12 22 101 63 87 88 77 69; set tos 9 73 9 9 9 9 9 74 74"
    set literal_transitions[75] "set inputs 12 101 29 63 36 59 87 88 111; set tos 76 61 77 61 78 79 61 61 56"
    set literal_transitions[77] "set inputs 36 59 87 88 101 29 63; set tos 78 79 61 61 61 77 61"
    set literal_transitions[78] "set inputs 9 41; set tos 77 77"
    set literal_transitions[79] "set inputs 105 27 67 76; set tos 77 77 77 77"
    set literal_transitions[80] "set inputs 51 65; set tos 80 80"
    set literal_transitions[81] "set inputs 78 117 49; set tos 16 16 16"
    set literal_transitions[83] "set inputs 30 2 91 94 53 68; set tos 135 83 135 82 83 2"
    set literal_transitions[84] "set inputs 104 2 94 53 47 44; set tos 47 47 46 47 84 84"
    set literal_transitions[85] "set inputs 84 42 75 53 90 89; set tos 43 43 36 36 37 43"
    set literal_transitions[86] "set inputs 39; set tos 43"
    set literal_transitions[87] "set inputs 110 101 22 63 87 88 77; set tos 63 63 63 63 63 63 88"
    set literal_transitions[88] "set inputs 87 88 110 101 22 63; set tos 63 63 63 63 63 63"
    set literal_transitions[89] "set inputs 17 4 7 95; set tos 90 90 90 90"
    set literal_transitions[92] "set inputs 17 4 7 12 95; set tos 90 90 90 91 90"
    set literal_transitions[93] "set inputs 2 94 53 33; set tos 93 94 93 95"
    set literal_transitions[95] "set inputs 104 2 94 53 33; set tos 93 93 94 93 95"
    set literal_transitions[96] "set inputs 56; set tos 5"
    set literal_transitions[97] "set inputs 110 56 22 101 63 87 88 77; set tos 6 98 6 6 6 6 6 99"
    set literal_transitions[99] "set inputs 110 101 56 22 63 87 88 77; set tos 6 6 98 6 6 6 6 99"
    set literal_transitions[100] "set inputs 63 37 6 72 101 83; set tos 43 56 43 43 43 43"
    set literal_transitions[101] "set inputs 9 41; set tos 69 69"
    set literal_transitions[102] "set inputs 65 12 69; set tos 102 104 102"
    set literal_transitions[103] "set inputs 65 12 69; set tos 65 64 65"
    set literal_transitions[105] "set inputs 65 12 34 50; set tos 48 49 50 50"
    set literal_transitions[107] "set inputs 9 41; set tos 61 61"
    set literal_transitions[108] "set inputs 51 65 110 22 77; set tos 80 80 63 63 62"
    set literal_transitions[109] "set inputs 11 2 71 109 56 94 68 46 53 82; set tos 109 32 20 109 22 33 26 25 32 109"
    set literal_transitions[110] "set inputs 74 40 13 23; set tos 111 111 111 111"
    set literal_transitions[111] "set inputs 65; set tos 43"
    set literal_transitions[113] "set inputs 115; set tos 43"
    set literal_transitions[115] "set inputs 65 40 13 23 74; set tos 110 111 111 111 111"
    set literal_transitions[119] "set inputs 65; set tos 118"
    set literal_transitions[120] "set inputs 110 22 77 69; set tos 18 18 120 120"
    set literal_transitions[121] "set inputs 87 88 12 101 63; set tos 43 43 116 43 43"
    set literal_transitions[122] "set inputs 93 97; set tos 122 122"
    set literal_transitions[123] "set inputs 110 56 22 101 63 87 88 77; set tos 6 112 6 6 6 6 6 99"
    set literal_transitions[124] "set inputs 10 92 12 21 57 78 45 73 43 116 117; set tos 51 51 34 51 51 51 51 51 51 51 51"
    set literal_transitions[125] "set inputs 85; set tos 43"
    set literal_transitions[126] "set inputs 110 12 22 101 63 87 88 65 77 69; set tos 9 133 9 9 9 9 9 102 74 126"
    set literal_transitions[127] "set inputs 2 91 94 44 30 86 53 68; set tos 136 135 137 24 135 24 136 2"
    set literal_transitions[128] "set inputs 69 65 110 12 77 22; set tos 128 55 18 54 120 18"
    set literal_transitions[129] "set inputs 65 34 8 50; set tos 134 111 43 111"
    set literal_transitions[130] "set inputs 81 65 12 34 50; set tos 131 10 29 13 14"
    set literal_transitions[131] "set inputs 81 65 12 50; set tos 131 11 132 14"
    set literal_transitions[134] "set inputs 34 50; set tos 111 111"
    set literal_transitions[135] "set inputs 30 2 104 91 94 53 68; set tos 135 83 83 135 82 83 2"
    set literal_transitions[136] "set inputs 2 91 94 44 30 86 53 68; set tos 83 135 82 24 135 24 83 2"
    set literal_transitions[138] "set inputs 53 75; set tos 138 138"

    set --local match_anything_transitions_from 7 54 76 112 34 37 128 66 96 123 80 133 46 106 119 5 29 82 25 20 56 94 114 31 33 108 103 118 132 64 70 26 55 109 53 3 137 117 2 116 97 126 91 59 41 22 102 72 52 49 27 104 98 8 73 23 87 57 12 17
    set --local match_anything_transitions_to 6 55 43 97 35 138 65 45 96 96 38 126 47 43 111 43 30 83 32 32 43 93 43 31 32 38 103 111 131 65 69 109 65 109 14 3 136 50 3 42 96 103 89 106 39 31 103 105 52 48 28 102 99 9 74 21 52 58 11 81
    set subword_transitions[90] "set subword_ids 1; set tos 16"

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

    set command_states 7 54 76 64 70 112 26 55 109 53 3 34 137 117 37 128 2 116 97 126 66 96 91 59 123 72 41 22 80 102 133 52 49 27 46 106 119 5 104 29 82 98 25 8 73 23 20 87 57 56 94 114 31 33 12 108 17 103 118 132
    set command_ids 53 60 60 60 60 53 39 53 39 60 39 60 57 60 6 53 39 60 57 57 60 57 60 44 57 60 57 53 53 57 60 57 60 60 57 58 53 53 60 60 57 53 19 60 60 57 20 57 58 57 57 44 53 57 60 53 60 57 53 60
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
