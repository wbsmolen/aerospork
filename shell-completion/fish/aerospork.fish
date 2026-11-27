function _aerospork_56
    set 1 $argv[1]
    true
end

function _aerospork_24
    set 1 $argv[1]
    aerospork list-apps --format '%{app-bundle-id}%{tab}%{app-name}'
end

function _aerospork_25
    set 1 $argv[1]
    aerospork list-apps --format '%{app-pid}%{tab}%{app-name}'
end

function _aerospork_59
    set 1 $argv[1]
    aerospork config --get mode --keys | xargs -I{} aerospork config --get mode.{}.binding --keys
end

function _aerospork_53
    set 1 $argv[1]
    aerospork config --get mode --keys
end

function _aerospork_62
    set 1 $argv[1]
    aerospork list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
end

function _aerospork_55
    set 1 $argv[1]
    aerospork list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
end

function _aerospork_60
    set 1 $argv[1]
    aerospork list-workspaces --all
end

function _aerospork_10
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

    set --local literals "move-mouse" "--count" "mode-changed" "-v" "smart" "macos-native-fullscreen" "mute-toggle" "height" "toggle" "all-monitors-outer-frame" "h_accordion" "all" "--window-id" "monitor-force-center" "list-apps" "flatten-workspace-tree" "mode" "width" "summon-workspace" "focus-back-and-forth" "list-monitors" "h_tiles" "prev" "window-force-center" "trigger-binding" "-h" "move-node-to-workspace" "wrap-around-the-workspace" "enable" "focused-monitor-changed" "--ignore-floating" "--visible" "close-all-windows-but-current" "--help" "--macos-native-hidden" "off" "move-workspace-to-monitor" "--boundaries" "set" "workspace-back-and-forth" "--quit-if-last-window" "window-lazy-center" "workspace" "--major-keys" "accordion" "--focused" "tiling" "--app-bundle-id" "--mouse" "balance-sizes" "opposite" "sticky" "on" "--auto-back-and-forth" "--version" "--json" "join-with" "reload-config" "--workspace" "floating" "--swap-focus" "--mode" "--boundaries-action" "resize" "visible" "close" "up" "layout" "--fail-if-noop" "--tree" "fail" "list-exec-env-vars" "--focus-follows-window" "split" "--monitor" "--pid" "mute-on" "v_tiles" "monitor-lazy-center" "--keys" "wrap-around-all-monitors" "--wrap-around" "subscribe" "horizontal" "create-implicit-container" "config" "--no-outer-gaps" "focused" "mute-off" "--all-keys" "--show-secrets" "workspace-windows-changed" "--all" "left" "right" "swap" "--config-path" "--get" "--empty" "tiles" "--no-gui" "dfs-next" "smart-opposite" "--format" "list-modes" "focus-changed" "--dry-run" "window-detected" "move-node-to-monitor" "dfs-prev" "move" "focus" "down" "list-workspaces" "volume" "no" "stop" "debug-windows" "macos-native-minimize" "list-windows" "mouse" "next" "--dfs-index" "open-settings" "fullscreen" "focus-monitor" "focused-workspace-changed" "--current" "v_accordion" "vertical"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 4 57 58 37 6 40 64 96 66 105 15 43 68 72 16 109 74 21 17 20 111 112 19 25 26 114 27 115 118 119 120 29 83 50 86 52 124 33 55 125 34 126; set tos 117 15 128 86 129 68 15 71 101 119 74 89 109 130 16 2 67 78 20 121 15 8 131 123 57 15 97 132 21 133 79 27 134 112 2 135 68 15 81 15 108 15 125"
    set literal_transitions[2] "set inputs 59; set tos 3"
    set literal_transitions[4] "set inputs 69 13 73; set tos 4 5 4"
    set literal_transitions[6] "set inputs 13 69 73; set tos 50 6 6"
    set literal_transitions[8] "set inputs 38 63 94 95 13 113 67; set tos 95 96 45 45 7 45 45"
    set literal_transitions[9] "set inputs 38 63 94 95 113 31 67; set tos 10 11 12 12 12 9 12"
    set literal_transitions[10] "set inputs 10 43; set tos 9 9"
    set literal_transitions[11] "set inputs 117 28 71 81; set tos 9 9 9 9"
    set literal_transitions[12] "set inputs 38 63 31; set tos 111 144 12"
    set literal_transitions[13] "set inputs 3 106 92 108 127 30; set tos 13 13 13 13 13 13"
    set literal_transitions[16] "set inputs 91; set tos 15"
    set literal_transitions[18] "set inputs 69 13 73; set tos 18 17 18"
    set literal_transitions[20] "set inputs 2 104 56 49 46; set tos 20 19 20 60 60"
    set literal_transitions[21] "set inputs 67 39 7 77 113 89; set tos 15 14 15 15 15 15"
    set literal_transitions[22] "set inputs 87 69 13 36 53; set tos 23 23 24 25 26"
    set literal_transitions[23] "set inputs 87 69 13 53; set tos 23 23 24 26"
    set literal_transitions[25] "set inputs 13 69; set tos 82 15"
    set literal_transitions[26] "set inputs 13 87 69; set tos 120 26 26"
    set literal_transitions[27] "set inputs 76 2 59 104 46 93 48 56 75; set tos 28 29 30 31 32 32 33 29 34"
    set literal_transitions[29] "set inputs 76 2 59 104 46 93 48 56 75; set tos 28 83 30 84 32 32 33 83 34"
    set literal_transitions[30] "set inputs 88 65; set tos 92 92"
    set literal_transitions[32] "set inputs 104 2 56; set tos 14 15 15"
    set literal_transitions[34] "set inputs 12 121 88; set tos 105 105 105"
    set literal_transitions[36] "set inputs 87 69 13 36 53; set tos 51 23 52 25 26"
    set literal_transitions[37] "set inputs 54 69; set tos 37 37"
    set literal_transitions[38] "set inputs 23 122; set tos 39 39"
    set literal_transitions[39] "set inputs 82; set tos 15"
    set literal_transitions[41] "set inputs 32 2 99 104 56 75; set tos 99 41 99 40 41 75"
    set literal_transitions[42] "set inputs 122 113 59 23 67 94 95 82; set tos 43 43 44 43 43 43 43 42"
    set literal_transitions[43] "set inputs 59 82; set tos 139 43"
    set literal_transitions[45] "set inputs 13 38 63; set tos 46 47 48"
    set literal_transitions[47] "set inputs 10 43; set tos 45 45"
    set literal_transitions[48] "set inputs 71 85 117; set tos 45 45 45"
    set literal_transitions[49] "set inputs 69 13 73; set tos 6 50 6"
    set literal_transitions[51] "set inputs 87 69 13 53; set tos 51 23 52 26"
    set literal_transitions[53] "set inputs 79 42 14 24; set tos 54 54 54 54"
    set literal_transitions[54] "set inputs 69; set tos 15"
    set literal_transitions[55] "set inputs 122 59 23 113 67 94 95 82; set tos 43 44 43 43 43 43 43 42"
    set literal_transitions[56] "set inputs 59; set tos 3"
    set literal_transitions[57] "set inputs 62; set tos 59"
    set literal_transitions[58] "set inputs 62; set tos 121"
    set literal_transitions[60] "set inputs 116 2 104 56 49 46; set tos 20 20 19 20 60 60"
    set literal_transitions[61] "set inputs 69 13 36 53; set tos 61 62 63 63"
    set literal_transitions[63] "set inputs 13 69; set tos 77 63"
    set literal_transitions[64] "set inputs 94 95 113 67; set tos 15 15 15 15"
    set literal_transitions[67] "set inputs 122 13 23 113 67 94 95 69 82 73; set tos 137 66 137 137 137 137 137 18 142 67"
    set literal_transitions[68] "set inputs 69 13 36 53; set tos 61 69 63 63"
    set literal_transitions[70] "set inputs 56 80; set tos 70 70"
    set literal_transitions[71] "set inputs 18 5 8 13 103; set tos 72 72 72 73 72"
    set literal_transitions[74] "set inputs 128 56; set tos 74 74"
    set literal_transitions[75] "set inputs 12 121 88; set tos 76 76 76"
    set literal_transitions[76] "set inputs 12 2 121 99 104 32 56 88; set tos 76 104 76 115 103 115 104 76"
    set literal_transitions[78] "set inputs 51 13 84 130; set tos 79 80 79 79"
    set literal_transitions[79] "set inputs 13; set tos 82"
    set literal_transitions[81] "set inputs 41; set tos 15"
    set literal_transitions[83] "set inputs 76 2 48 59 56 75 104; set tos 28 83 33 30 83 34 84"
    set literal_transitions[86] "set inputs 101 107; set tos 86 86"
    set literal_transitions[87] "set inputs 56 98 80; set tos 87 88 87"
    set literal_transitions[89] "set inputs 2 104 56 35; set tos 89 90 89 91"
    set literal_transitions[91] "set inputs 116 2 104 56 35; set tos 89 89 90 89 91"
    set literal_transitions[92] "set inputs 76 2 65 59 104 48 56 88 75; set tos 28 83 92 30 84 33 83 92 34"
    set literal_transitions[93] "set inputs 13 61 82; set tos 94 93 93"
    set literal_transitions[95] "set inputs 10 43; set tos 8 8"
    set literal_transitions[96] "set inputs 71 85 117; set tos 8 8 8"
    set literal_transitions[97] "set inputs 2 99 104 46 32 93 56 75; set tos 98 99 100 32 99 32 98 75"
    set literal_transitions[98] "set inputs 2 99 104 46 32 93 56 75; set tos 41 99 40 32 99 32 41 75"
    set literal_transitions[99] "set inputs 32 2 116 99 104 56 75; set tos 99 41 41 99 40 41 75"
    set literal_transitions[101] "set inputs 113 13 102 61 67 94 95 82 110; set tos 93 102 93 101 93 93 93 101 93"
    set literal_transitions[104] "set inputs 32 2 99 104 56; set tos 115 104 115 103 104"
    set literal_transitions[105] "set inputs 12 2 76 121 59 104 75 48 56 88; set tos 105 83 28 105 30 84 34 33 83 105"
    set literal_transitions[106] "set inputs 11 22 60 84 100 47 78 45 129 130; set tos 107 107 107 107 107 107 107 107 107 107"
    set literal_transitions[107] "set inputs 11 22 60 84 100 47 78 45 129 130; set tos 107 107 107 107 107 107 107 107 107 107"
    set literal_transitions[108] "set inputs 87 69 13 36 53; set tos 51 22 35 25 26"
    set literal_transitions[109] "set inputs 54 69 122 23 82; set tos 110 110 39 39 38"
    set literal_transitions[110] "set inputs 54 69; set tos 110 110"
    set literal_transitions[111] "set inputs 10 43; set tos 12 12"
    set literal_transitions[112] "set inputs 3 93 92 106 108 30 127; set tos 13 15 13 13 13 13 13"
    set literal_transitions[113] "set inputs 122 23 82 73; set tos 114 114 113 113"
    set literal_transitions[114] "set inputs 82 73; set tos 114 114"
    set literal_transitions[115] "set inputs 32 2 116 99 104 56; set tos 115 104 104 115 103 104"
    set literal_transitions[116] "set inputs 18 5 8 103; set tos 72 72 72 72"
    set literal_transitions[117] "set inputs 69 42 14 24 79; set tos 53 54 54 54 54"
    set literal_transitions[119] "set inputs 13 41; set tos 118 119"
    set literal_transitions[123] "set inputs 69; set tos 124"
    set literal_transitions[125] "set inputs 122 113 23 67 94 95 82; set tos 39 39 39 39 39 39 127"
    set literal_transitions[127] "set inputs 94 95 122 113 23 67; set tos 39 39 39 39 39 39"
    set literal_transitions[128] "set inputs 94 95 13 113 67; set tos 15 15 85 15 15"
    set literal_transitions[129] "set inputs 122 59 23 113 67 94 95 82; set tos 43 138 43 43 43 43 43 42"
    set literal_transitions[130] "set inputs 11 100 13 22 60 84 47 78 45 129 130; set tos 107 107 122 107 107 107 107 107 107 107 107"
    set literal_transitions[131] "set inputs 13 113 31 67 38 63 94 95 123; set tos 82 12 9 12 10 11 12 12 14"
    set literal_transitions[132] "set inputs 73 69 122 13 82 23; set tos 132 4 114 5 113 114"
    set literal_transitions[133] "set inputs 13 70; set tos 82 15"
    set literal_transitions[134] "set inputs 69 36 9 53; set tos 145 54 15 54"
    set literal_transitions[135] "set inputs 90 44 80 56 98 97; set tos 15 15 87 87 88 15"
    set literal_transitions[137] "set inputs 13 82 73; set tos 136 137 137"
    set literal_transitions[140] "set inputs 84 130 51; set tos 79 79 79"
    set literal_transitions[142] "set inputs 122 13 23 113 67 94 95 82 73; set tos 137 141 137 137 137 137 137 142 142"
    set literal_transitions[143] "set inputs 69 13 36 53; set tos 61 62 63 63"
    set literal_transitions[144] "set inputs 117 28 71 81; set tos 12 12 12 12"
    set literal_transitions[145] "set inputs 36 53; set tos 54 54"

    set --local match_anything_transitions_from 7 76 40 24 34 125 122 44 66 88 136 123 80 46 85 5 105 82 14 65 56 94 31 33 28 69 103 118 139 132 50 55 109 129 3 138 124 77 126 59 67 4 92 102 52 49 120 100 18 19 62 84 121 30 75 90 73 35 57 110 17 141
    set --local match_anything_transitions_to 8 76 41 23 105 126 106 42 67 70 137 54 140 45 64 4 105 15 15 15 56 93 29 83 83 143 104 119 43 6 6 56 37 56 15 55 54 63 126 65 49 6 92 101 51 49 26 98 49 20 61 83 15 92 76 89 116 36 58 37 18 142
    set subword_transitions[72] "set subword_ids 1; set tos 79"

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

    set command_states 7 76 50 129 55 40 24 109 3 124 34 138 77 125 122 44 126 66 88 59 136 123 67 4 102 80 92 52 49 46 85 5 120 100 105 18 19 62 84 82 121 30 14 75 90 65 73 35 57 56 94 110 31 33 69 28 17 103 118 139 141 132
    set command_ids 62 55 62 56 56 56 62 60 60 60 55 60 62 56 62 60 56 62 10 53 62 60 56 60 62 62 60 62 56 62 62 62 62 56 55 56 56 62 56 62 53 60 56 55 56 59 62 62 59 56 62 60 56 24 62 25 62 56 62 60 62 60
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
