function _aerospork_60
    set 1 $argv[1]
    true
end

function _aerospork_43
    set 1 $argv[1]
    aerospork list-apps --format '%{app-bundle-id}%{tab}%{app-name}'
end

function _aerospork_50
    set 1 $argv[1]
    aerospork list-apps --format '%{app-pid}%{tab}%{app-name}'
end

function _aerospork_31
    set 1 $argv[1]
    aerospork config --get mode --keys | xargs -I{} aerospork config --get mode.{}.binding --keys
end

function _aerospork_40
    set 1 $argv[1]
    aerospork config --get mode --keys
end

function _aerospork_63
    set 1 $argv[1]
    aerospork list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
end

function _aerospork_58
    set 1 $argv[1]
    aerospork list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
end

function _aerospork_54
    set 1 $argv[1]
    aerospork list-workspaces --all
end

function _aerospork_12
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

    set --local literals "move-mouse" "--count" "mode-changed" "-v" "smart" "macos-native-fullscreen" "mute-toggle" "height" "toggle" "all-monitors-outer-frame" "h_accordion" "all" "--window-id" "monitor-force-center" "list-apps" "flatten-workspace-tree" "mode" "width" "summon-workspace" "focus-back-and-forth" "list-monitors" "h_tiles" "prev" "window-force-center" "trigger-binding" "-h" "move-node-to-workspace" "wrap-around-the-workspace" "enable" "focused-monitor-changed" "--ignore-floating" "--visible" "close-all-windows-but-current" "--help" "--macos-native-hidden" "scratchpad" "off" "move-workspace-to-monitor" "--boundaries" "set" "workspace-back-and-forth" "--quit-if-last-window" "window-lazy-center" "workspace" "--major-keys" "accordion" "--focused" "tiling" "--app-bundle-id" "--mouse" "balance-sizes" "opposite" "sticky" "on" "--auto-back-and-forth" "--version" "--json" "join-with" "reload-config" "--workspace" "floating" "--swap-focus" "--mode" "--boundaries-action" "resize" "visible" "close" "up" "layout" "--fail-if-noop" "--tree" "fail" "list-exec-env-vars" "--focus-follows-window" "split" "--monitor" "--pid" "mute-on" "v_tiles" "monitor-lazy-center" "--keys" "wrap-around-all-monitors" "--wrap-around" "subscribe" "horizontal" "create-implicit-container" "config" "--no-outer-gaps" "focused" "mute-off" "--all-keys" "--show-secrets" "move-node-to-scratchpad" "workspace-windows-changed" "--all" "left" "right" "swap" "--config-path" "--get" "--empty" "tiles" "--no-gui" "dfs-next" "smart-opposite" "--format" "list-modes" "focus-changed" "--dry-run" "window-detected" "move-node-to-monitor" "dfs-prev" "move" "focus" "down" "list-workspaces" "volume" "no" "stop" "debug-windows" "macos-native-minimize" "list-windows" "mouse" "next" "--dfs-index" "open-settings" "fullscreen" "focus-monitor" "focused-workspace-changed" "--current" "v_accordion" "vertical"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 4 58 36 59 93 38 6 41 65 98 67 107 15 44 69 73 16 111 17 21 75 20 113 114 19 25 26 116 27 117 120 121 122 29 84 51 87 53 126 33 56 127 34 128; set tos 120 31 88 125 67 64 110 61 31 126 117 45 98 91 127 19 76 2 128 124 77 114 31 60 27 121 53 31 129 130 81 30 96 119 131 132 2 104 61 31 80 31 14 31 133"
    set literal_transitions[2] "set inputs 60; set tos 3"
    set literal_transitions[6] "set inputs 13 62 83; set tos 7 6 6"
    set literal_transitions[8] "set inputs 39 64 96 97 115 31 68; set tos 9 10 11 11 11 8 11"
    set literal_transitions[9] "set inputs 10 44; set tos 8 8"
    set literal_transitions[10] "set inputs 119 28 72 82; set tos 8 8 8 8"
    set literal_transitions[11] "set inputs 39 64 31; set tos 138 139 11"
    set literal_transitions[13] "set inputs 13 88 70; set tos 12 13 13"
    set literal_transitions[14] "set inputs 88 70 13 37 54; set tos 15 16 17 18 13"
    set literal_transitions[15] "set inputs 88 70 13 54; set tos 15 85 86 13"
    set literal_transitions[16] "set inputs 88 70 13 37 54; set tos 85 85 94 18 13"
    set literal_transitions[18] "set inputs 13 70; set tos 28 31"
    set literal_transitions[19] "set inputs 11 102 13 22 61 85 48 79 46 131 132; set tos 20 20 21 20 20 20 20 20 20 20 20"
    set literal_transitions[20] "set inputs 11 22 61 85 102 48 79 46 131 132; set tos 20 20 20 20 20 20 20 20 20 20"
    set literal_transitions[23] "set inputs 32 2 101 106 57; set tos 32 23 32 22 23"
    set literal_transitions[24] "set inputs 70 13 74; set tos 24 25 24"
    set literal_transitions[26] "set inputs 13 70 74; set tos 52 26 26"
    set literal_transitions[27] "set inputs 13 115 31 68 39 64 96 97 125; set tos 28 11 8 11 9 10 11 11 29"
    set literal_transitions[30] "set inputs 13 71; set tos 28 31"
    set literal_transitions[32] "set inputs 32 2 118 101 106 57; set tos 32 23 23 32 22 23"
    set literal_transitions[33] "set inputs 72 86 119; set tos 34 34 34"
    set literal_transitions[34] "set inputs 13 39 64; set tos 87 142 33"
    set literal_transitions[35] "set inputs 11 22 61 85 102 48 79 46 131 132; set tos 20 20 20 20 20 20 20 20 20 20"
    set literal_transitions[36] "set inputs 3 108 94 110 129 30; set tos 36 36 36 36 36 36"
    set literal_transitions[38] "set inputs 70; set tos 31"
    set literal_transitions[40] "set inputs 70 13 74; set tos 40 42 40"
    set literal_transitions[41] "set inputs 70 13 74; set tos 26 52 26"
    set literal_transitions[43] "set inputs 96 97 115 68; set tos 31 31 31 31"
    set literal_transitions[45] "set inputs 13 42; set tos 44 45"
    set literal_transitions[46] "set inputs 32 2 118 101 106 57 76; set tos 46 47 47 46 48 47 49"
    set literal_transitions[47] "set inputs 32 2 101 106 57 76; set tos 46 47 46 48 47 49"
    set literal_transitions[49] "set inputs 12 123 89; set tos 55 55 55"
    set literal_transitions[51] "set inputs 13 83 74; set tos 50 51 51"
    set literal_transitions[53] "set inputs 63; set tos 4"
    set literal_transitions[54] "set inputs 63; set tos 124"
    set literal_transitions[55] "set inputs 12 2 123 101 106 32 57 89; set tos 55 23 55 32 22 32 23 55"
    set literal_transitions[56] "set inputs 83 74; set tos 56 56"
    set literal_transitions[57] "set inputs 12 123 89; set tos 58 58 58"
    set literal_transitions[58] "set inputs 12 2 77 123 60 106 76 49 57 89; set tos 58 99 100 58 68 101 57 102 99 58"
    set literal_transitions[59] "set inputs 72 86 119; set tos 60 60 60"
    set literal_transitions[60] "set inputs 39 64 96 97 13 115 68; set tos 75 59 34 34 97 34 34"
    set literal_transitions[61] "set inputs 70 13 37 54; set tos 62 63 64 64"
    set literal_transitions[62] "set inputs 70 13 37 54; set tos 62 90 64 64"
    set literal_transitions[64] "set inputs 13 70; set tos 70 64"
    set literal_transitions[65] "set inputs 96 97 124 115 23 68; set tos 66 66 66 66 66 66"
    set literal_transitions[66] "set inputs 83; set tos 31"
    set literal_transitions[67] "set inputs 103 109; set tos 67 67"
    set literal_transitions[68] "set inputs 89 66; set tos 69 69"
    set literal_transitions[69] "set inputs 77 2 66 60 106 49 57 89 76; set tos 100 99 69 68 101 102 99 69 57"
    set literal_transitions[72] "set inputs 124 60 23 115 68 96 97 83; set tos 73 113 73 73 73 73 73 112"
    set literal_transitions[73] "set inputs 60 83; set tos 74 73"
    set literal_transitions[75] "set inputs 10 44; set tos 60 60"
    set literal_transitions[76] "set inputs 92; set tos 31"
    set literal_transitions[77] "set inputs 2 106 57 50 47; set tos 77 78 77 79 79"
    set literal_transitions[79] "set inputs 118 2 106 57 50 47; set tos 77 77 78 77 79 79"
    set literal_transitions[80] "set inputs 42; set tos 31"
    set literal_transitions[81] "set inputs 68 40 7 78 115 90; set tos 31 29 31 31 31 31"
    set literal_transitions[83] "set inputs 70 13 37 54; set tos 62 90 64 64"
    set literal_transitions[84] "set inputs 88 70 13 37 54; set tos 15 85 86 18 13"
    set literal_transitions[85] "set inputs 88 70 13 54; set tos 85 85 94 13"
    set literal_transitions[88] "set inputs 96 97 13 115 68; set tos 31 31 89 31 31"
    set literal_transitions[91] "set inputs 2 106 57 35; set tos 91 92 91 93"
    set literal_transitions[93] "set inputs 118 2 106 57 35; set tos 91 91 92 91 93"
    set literal_transitions[95] "set inputs 85 132 52; set tos 96 96 96"
    set literal_transitions[96] "set inputs 13; set tos 28"
    set literal_transitions[98] "set inputs 130 57; set tos 98 98"
    set literal_transitions[99] "set inputs 77 2 49 60 57 76 106; set tos 100 99 102 68 99 57 101"
    set literal_transitions[104] "set inputs 91 45 81 57 100 99; set tos 31 31 105 105 106 31"
    set literal_transitions[105] "set inputs 57 100 81; set tos 105 106 105"
    set literal_transitions[108] "set inputs 77 2 60 106 47 95 49 57 76; set tos 100 99 68 101 109 109 102 99 57"
    set literal_transitions[109] "set inputs 106 2 57; set tos 29 31 31"
    set literal_transitions[110] "set inputs 124 60 23 115 68 96 97 83; set tos 73 71 73 73 73 73 73 112"
    set literal_transitions[111] "set inputs 60; set tos 3"
    set literal_transitions[112] "set inputs 124 115 60 23 68 96 97 83; set tos 73 73 113 73 73 73 73 112"
    set literal_transitions[114] "set inputs 52 13 85 132; set tos 96 103 96 96"
    set literal_transitions[117] "set inputs 115 13 104 62 68 96 97 83 112; set tos 6 116 6 117 6 6 6 117 6"
    set literal_transitions[118] "set inputs 80 43 14 24; set tos 38 38 38 38"
    set literal_transitions[119] "set inputs 77 2 60 106 47 95 49 57 76; set tos 100 108 68 107 109 109 102 108 57"
    set literal_transitions[120] "set inputs 70 43 14 24 80; set tos 118 38 38 38 38"
    set literal_transitions[121] "set inputs 70; set tos 37"
    set literal_transitions[123] "set inputs 18 5 8 105; set tos 115 115 115 115"
    set literal_transitions[125] "set inputs 49; set tos 39"
    set literal_transitions[126] "set inputs 18 5 8 13 105; set tos 115 115 115 122 115"
    set literal_transitions[127] "set inputs 55 70 124 23 83; set tos 146 146 66 66 144"
    set literal_transitions[128] "set inputs 124 13 23 115 68 96 97 70 83 74; set tos 51 141 51 51 51 51 51 40 134 128"
    set literal_transitions[129] "set inputs 2 101 106 47 32 95 57 76; set tos 145 46 147 109 46 109 145 49"
    set literal_transitions[130] "set inputs 74 70 124 13 83 23; set tos 130 24 56 25 140 56"
    set literal_transitions[131] "set inputs 70 37 9 54; set tos 143 38 31 38"
    set literal_transitions[132] "set inputs 3 95 94 108 110 30 129; set tos 36 31 36 36 36 36 36"
    set literal_transitions[133] "set inputs 124 115 23 68 96 97 83; set tos 66 66 66 66 66 66 65"
    set literal_transitions[134] "set inputs 124 13 23 115 68 96 97 83 74; set tos 51 135 51 51 51 51 51 134 134"
    set literal_transitions[136] "set inputs 57 81; set tos 136 136"
    set literal_transitions[137] "set inputs 55 70; set tos 137 137"
    set literal_transitions[138] "set inputs 10 44; set tos 11 11"
    set literal_transitions[139] "set inputs 119 28 72 82; set tos 11 11 11 11"
    set literal_transitions[140] "set inputs 124 23 83 74; set tos 56 56 140 140"
    set literal_transitions[142] "set inputs 10 44; set tos 34 34"
    set literal_transitions[143] "set inputs 37 54; set tos 38 38"
    set literal_transitions[144] "set inputs 23 124; set tos 66 66"
    set literal_transitions[145] "set inputs 2 101 106 47 32 95 57 76; set tos 47 46 48 109 46 109 47 49"
    set literal_transitions[146] "set inputs 55 70; set tos 146 146"

    set --local match_anything_transitions_from 7 24 40 48 37 128 146 122 127 44 133 106 86 5 21 29 82 25 68 101 63 94 111 69 28 103 89 70 50 55 53 39 58 3 124 116 135 97 42 4 22 41 102 72 92 49 52 71 130 100 107 113 121 74 90 78 87 57 147 110 12 17 141
    set --local match_anything_transitions_to 6 26 41 47 38 41 137 123 137 45 82 136 15 31 35 31 82 24 69 99 83 85 111 69 31 95 43 64 51 55 54 31 58 31 31 117 134 60 40 5 23 41 99 111 91 55 26 72 26 99 108 112 38 73 62 77 34 58 145 111 13 84 128
    set subword_transitions[115] "set subword_ids 1; set tos 96"

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

    set command_states 7 70 50 55 24 40 53 39 48 58 3 124 37 128 146 122 127 116 135 44 97 42 4 22 41 102 72 133 92 49 52 71 106 86 130 5 100 21 29 107 82 113 25 121 74 90 78 68 101 87 57 63 94 147 110 111 12 69 28 17 103 141 89
    set command_ids 63 63 63 58 54 60 31 43 60 58 54 40 54 60 54 63 54 63 63 63 63 63 40 60 60 43 60 60 60 58 63 54 12 63 54 31 50 63 60 60 60 54 63 54 54 63 60 54 60 63 58 63 63 60 60 60 63 54 63 63 63 63 63
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
