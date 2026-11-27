function _aerospork_59
    set 1 $argv[1]
    true
end

function _aerospork_30
    set 1 $argv[1]
    aerospork list-apps --format '%{app-bundle-id}%{tab}%{app-name}'
end

function _aerospork_52
    set 1 $argv[1]
    aerospork list-apps --format '%{app-pid}%{tab}%{app-name}'
end

function _aerospork_62
    set 1 $argv[1]
    aerospork config --get mode --keys | xargs -I{} aerospork config --get mode.{}.binding --keys
end

function _aerospork_47
    set 1 $argv[1]
    aerospork config --get mode --keys
end

function _aerospork_56
    set 1 $argv[1]
    aerospork list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
end

function _aerospork_60
    set 1 $argv[1]
    aerospork list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
end

function _aerospork_61
    set 1 $argv[1]
    aerospork list-workspaces --all
end

function _aerospork_11
    set 1 $argv[1]
    aerospork config --major-keys
end

function _aerospork_subword_cmd_0
    true
end

function _aerospork_subword_1
    set mode $argv[1]
    set word $argv[2]

    set --local literals "+" "-"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 2; set tos 2 2"

    set --local match_anything_transitions_from 2 1
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

    set command_states 2 1
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

    set --local literals "resize" "mouse" "list-workspaces" "fullscreen" "stop" "tiles" "summon-workspace" "--dry-run" "mute-on" "--visible" "--major-keys" "-h" "--no-gui" "--boundaries-action" "reload-config" "--count" "--config-path" "right" "floating" "--quit-if-last-window" "list-modes" "workspace-back-and-forth" "window-lazy-center" "wrap-around-the-workspace" "--focus-follows-window" "move-mouse" "list-apps" "--format" "create-implicit-container" "on" "--tree" "monitor-lazy-center" "--version" "focus-back-and-forth" "--app-bundle-id" "monitor-force-center" "--empty" "--pid" "--workspace" "h_accordion" "accordion" "v_accordion" "mute-toggle" "window-force-center" "open-settings" "down" "config" "--show-secrets" "flatten-workspace-tree" "join-with" "move-workspace-to-monitor" "--dfs-index" "toggle" "--wrap-around" "macos-native-minimize" "move" "move-node-to-workspace" "dfs-next" "--all-keys" "all" "--mouse" "enable" "tiling" "no" "--mode" "close" "dfs-prev" "list-exec-env-vars" "--swap-focus" "debug-windows" "--all" "focused" "close-all-windows-but-current" "smart" "visible" "focus-monitor" "--macos-native-hidden" "--monitor" "--fail-if-noop" "off" "all-monitors-outer-frame" "width" "--current" "--ignore-floating" "h_tiles" "fail" "up" "--json" "--auto-back-and-forth" "mute-off" "trigger-binding" "v_tiles" "list-windows" "--window-id" "--keys" "balance-sizes" "layout" "--get" "--boundaries" "left" "smart-opposite" "vertical" "move-node-to-monitor" "split" "wrap-around-all-monitors" "sticky" "focus" "prev" "--help" "height" "workspace" "--no-outer-gaps" "horizontal" "set" "--focused" "swap" "opposite" "-v" "next" "macos-native-fullscreen" "list-monitors" "volume" "mode"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 73 27 1 121 33 103 34 76 3 104 4 106 107 7 109 12 45 15 47 51 49 50 111 55 56 57 91 93 116 118 62 21 96 22 66 97 68 120 122 70 123 26; set tos 2 34 4 35 6 7 6 8 9 10 11 12 13 14 6 6 6 15 16 18 19 17 20 21 22 23 24 25 26 6 27 28 19 6 29 30 31 12 3 32 5 33"
    set literal_transitions[2] "set inputs 20; set tos 6"
    set literal_transitions[3] "set inputs 9 87 46 43 90 114; set tos 6 6 6 6 6 73"
    set literal_transitions[4] "set inputs 74 94 101 110 82; set tos 133 134 133 133 133"
    set literal_transitions[7] "set inputs 94 54 87 100 108 119 25 46 18 79; set tos 113 80 81 81 81 81 7 81 81 60"
    set literal_transitions[8] "set inputs 108 54 87 100 119 46 18; set tos 87 131 87 87 87 87 87"
    set literal_transitions[9] "set inputs 88 10 78 115 71 28 37 16; set tos 106 64 63 107 107 108 64 106"
    set literal_transitions[10] "set inputs 94 113 102 117; set tos 128 21 21 21"
    set literal_transitions[11] "set inputs 30 80 94 112 79; set tos 44 45 140 47 141"
    set literal_transitions[12] "set inputs 30 80 94 79; set tos 36 36 124 52"
    set literal_transitions[13] "set inputs 52 94 87 99 100 14 46 18 84; set tos 73 74 75 76 75 77 75 75 78"
    set literal_transitions[14] "set inputs 79; set tos 142"
    set literal_transitions[15] "set inputs 13 8; set tos 15 15"
    set literal_transitions[16] "set inputs 11 17 59 88 95 98; set tos 6 6 6 125 125 69"
    set literal_transitions[17] "set inputs 94 87 18 46 100; set tos 114 6 6 6 6"
    set literal_transitions[18] "set inputs 39 54 87 100 108 119 46 18; set tos 105 97 99 99 99 99 99 99"
    set literal_transitions[19] "set inputs 39; set tos 61"
    set literal_transitions[20] "set inputs 79 108 54 119 89; set tos 121 87 86 87 121"
    set literal_transitions[21] "set inputs 94; set tos 74"
    set literal_transitions[22] "set inputs 94 14 46 18 87 99 100; set tos 136 89 42 42 42 130 42"
    set literal_transitions[23] "set inputs 25 54 94 108 119 79; set tos 23 116 39 117 117 38"
    set literal_transitions[24] "set inputs 65; set tos 49"
    set literal_transitions[25] "set inputs 38 39 88 35 78 115 71 28 16; set tos 91 92 72 94 55 107 107 71 72"
    set literal_transitions[26] "set inputs 94 54 58 87 100 67 69 46 18; set tos 84 26 85 85 85 85 26 85 85"
    set literal_transitions[27] "set inputs 30 53 80 79; set tos 54 6 54 53"
    set literal_transitions[28] "set inputs 83 88; set tos 28 28"
    set literal_transitions[29] "set inputs 94 20; set tos 137 29"
    set literal_transitions[30] "set inputs 6 40 41 85 42 63 94 102 113 19 92; set tos 67 67 67 67 67 67 127 67 67 67 67"
    set literal_transitions[31] "set inputs 48; set tos 6"
    set literal_transitions[32] "set inputs 31 94; set tos 6 74"
    set literal_transitions[33] "set inputs 23 44 32 36 79; set tos 54 54 54 54 135"
    set literal_transitions[34] "set inputs 77 88 28 16; set tos 143 34 88 34"
    set literal_transitions[35] "set inputs 115 88 61 28 16; set tos 118 35 118 119 35"
    set literal_transitions[36] "set inputs 94 79; set tos 37 36"
    set literal_transitions[38] "set inputs 25 94 79; set tos 38 39 38"
    set literal_transitions[40] "set inputs 25 94 79; set tos 40 101 40"
    set literal_transitions[41] "set inputs 29 86 5; set tos 42 42 42"
    set literal_transitions[42] "set inputs 94 14 99; set tos 132 41 139"
    set literal_transitions[43] "set inputs 30 80 94 112 79; set tos 44 45 46 47 48"
    set literal_transitions[44] "set inputs 112 94 79; set tos 44 83 44"
    set literal_transitions[45] "set inputs 94 79; set tos 74 6"
    set literal_transitions[47] "set inputs 30 94 112 79; set tos 44 46 47 48"
    set literal_transitions[48] "set inputs 30 94 112 79; set tos 44 58 48 48"
    set literal_transitions[52] "set inputs 30 80 94 79; set tos 36 36 51 52"
    set literal_transitions[53] "set inputs 30 80; set tos 54 54"
    set literal_transitions[54] "set inputs 79; set tos 6"
    set literal_transitions[55] "set inputs 2 60 72; set tos 56 56 56"
    set literal_transitions[56] "set inputs 38 39 88 35 2 60 78 28 72 16; set tos 91 92 90 94 56 56 55 93 56 90"
    set literal_transitions[57] "set inputs 30 80 94 79; set tos 36 36 51 52"
    set literal_transitions[60] "set inputs 25 94 79; set tos 60 59 60"
    set literal_transitions[62] "set inputs 78 88 10 28 37 16; set tos 63 62 64 65 64 62"
    set literal_transitions[63] "set inputs 2 60 72; set tos 110 110 110"
    set literal_transitions[64] "set inputs 16 78 88 10 28 64 37; set tos 62 63 62 64 65 62 64"
    set literal_transitions[66] "set inputs 6 40 41 85 42 63 102 113 19 92; set tos 67 67 67 67 67 67 67 67 67 67"
    set literal_transitions[67] "set inputs 6 40 41 85 42 63 102 113 19 92; set tos 67 67 67 67 67 67 67 67 67 67"
    set literal_transitions[68] "set inputs 65; set tos 5"
    set literal_transitions[70] "set inputs 88 95; set tos 70 70"
    set literal_transitions[72] "set inputs 38 39 88 35 78 115 71 28 16; set tos 91 92 90 94 55 107 107 93 90"
    set literal_transitions[75] "set inputs 84 14 99; set tos 75 126 111"
    set literal_transitions[76] "set inputs 111 81; set tos 78 78"
    set literal_transitions[77] "set inputs 24 86 105 5; set tos 78 78 78 78"
    set literal_transitions[78] "set inputs 99 14 46 100 18 84 87; set tos 76 77 75 75 75 78 75"
    set literal_transitions[80] "set inputs 94 54 87 100 108 119 25 46 18; set tos 79 80 81 81 81 81 80 81 81"
    set literal_transitions[81] "set inputs 25 54 94; set tos 81 81 82"
    set literal_transitions[85] "set inputs 94 54 69; set tos 109 85 85"
    set literal_transitions[86] "set inputs 108 119; set tos 87 87"
    set literal_transitions[87] "set inputs 54; set tos 6"
    set literal_transitions[89] "set inputs 29 86 5; set tos 22 22 22"
    set literal_transitions[90] "set inputs 16 39 78 88 28 35 38; set tos 90 92 55 90 93 94 91"
    set literal_transitions[92] "set inputs 75 72; set tos 115 115"
    set literal_transitions[95] "set inputs 39 54 87 100 108 119 46 18; set tos 96 97 99 99 99 99 99 99"
    set literal_transitions[97] "set inputs 39 54 87 100 108 119 46 18; set tos 96 97 99 99 99 99 99 99"
    set literal_transitions[98] "set inputs 39; set tos 61"
    set literal_transitions[99] "set inputs 39 54; set tos 120 99"
    set literal_transitions[100] "set inputs 25 94 79; set tos 40 101 40"
    set literal_transitions[102] "set inputs 88 10 28 37 16; set tos 102 103 104 103 102"
    set literal_transitions[103] "set inputs 16 88 10 28 64 37; set tos 102 102 103 104 102 103"
    set literal_transitions[106] "set inputs 88 10 78 115 71 28 37 16; set tos 62 64 63 107 107 65 64 62"
    set literal_transitions[107] "set inputs 16 28 88; set tos 6 73 6"
    set literal_transitions[110] "set inputs 37 88 10 2 60 28 72 16; set tos 103 102 103 110 110 104 110 102"
    set literal_transitions[111] "set inputs 111 81; set tos 75 75"
    set literal_transitions[112] "set inputs 46 18 87 100; set tos 6 6 6 6"
    set literal_transitions[115] "set inputs 72 39 75 88 38 35 78 28 16; set tos 115 92 115 90 91 94 55 93 90"
    set literal_transitions[116] "set inputs 25 54 108 119; set tos 116 116 117 117"
    set literal_transitions[117] "set inputs 25 54; set tos 117 117"
    set literal_transitions[118] "set inputs 115 88 61 28 64 16; set tos 118 35 118 119 35 35"
    set literal_transitions[121] "set inputs 79 89; set tos 121 121"
    set literal_transitions[122] "set inputs 89 79; set tos 122 122"
    set literal_transitions[125] "set inputs 98 88 95; set tos 69 125 125"
    set literal_transitions[126] "set inputs 24 86 105 5; set tos 75 75 75 75"
    set literal_transitions[129] "set inputs 113 102 117; set tos 21 21 21"
    set literal_transitions[130] "set inputs 111 81; set tos 22 22"
    set literal_transitions[131] "set inputs 108 87 18 46 100 119; set tos 87 87 87 87 87 87"
    set literal_transitions[135] "set inputs 23 44 32 36; set tos 54 54 54 54"
    set literal_transitions[138] "set inputs 74 110 101 82; set tos 133 133 133 133"
    set literal_transitions[139] "set inputs 111 81; set tos 42 42"
    set literal_transitions[141] "set inputs 30 80 94 112 79; set tos 44 45 58 48 48"
    set literal_transitions[143] "set inputs 77 88 28 64 16; set tos 143 34 88 34 34"

    set --local match_anything_transitions_from 92 88 140 38 104 73 84 96 128 121 69 120 65 136 55 123 115 49 101 56 100 124 93 39 61 50 114 79 98 94 58 105 95 74 60 37 83 113 46 20 18 59 127 134 137 14 5 108 23 132 109 91 51 110 8 82 119 71 7 63 142 24
    set --local match_anything_transitions_to 115 34 43 40 102 6 26 97 129 122 70 99 62 22 56 123 115 50 40 56 100 57 90 38 6 6 112 80 98 90 48 95 98 6 100 36 44 7 47 122 98 60 66 138 29 54 6 106 40 42 85 90 52 110 123 81 35 72 100 110 54 68
    set subword_transitions[133] "set subword_ids 1; set tos 21"

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

    set command_states 92 88 140 38 104 74 60 73 84 37 83 113 96 128 46 121 20 65 18 69 59 120 127 134 137 14 136 5 108 23 55 132 123 109 115 91 49 101 51 110 8 56 100 124 82 119 93 71 7 39 61 114 50 63 79 98 94 58 105 142 95 24
    set command_ids 61 59 56 61 59 56 59 59 56 56 56 56 61 56 56 61 61 59 59 11 56 61 56 56 56 61 56 47 59 61 60 56 59 56 61 52 47 56 56 60 59 60 59 56 56 59 59 59 59 56 61 56 62 60 56 59 30 56 61 61 59 62
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
