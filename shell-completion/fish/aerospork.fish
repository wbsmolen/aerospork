function _aerospork_59
    set 1 $argv[1]
    true
end

function _aerospork_31
    set 1 $argv[1]
    aerospork list-apps --format '%{app-bundle-id}%{tab}%{app-name}'
end

function _aerospork_47
    set 1 $argv[1]
    aerospork list-apps --format '%{app-pid}%{tab}%{app-name}'
end

function _aerospork_60
    set 1 $argv[1]
    aerospork config --get mode --keys | xargs -I{} aerospork config --get mode.{}.binding --keys
end

function _aerospork_61
    set 1 $argv[1]
    aerospork config --get mode --keys
end

function _aerospork_58
    set 1 $argv[1]
    aerospork list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
end

function _aerospork_39
    set 1 $argv[1]
    aerospork list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
end

function _aerospork_62
    set 1 $argv[1]
    aerospork list-workspaces --all
end

function _aerospork_23
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

    set --local literals "move-mouse" "--count" "-v" "smart" "macos-native-fullscreen" "mute-toggle" "height" "toggle" "all-monitors-outer-frame" "h_accordion" "all" "--window-id" "monitor-force-center" "list-apps" "flatten-workspace-tree" "mode" "width" "summon-workspace" "focus-back-and-forth" "list-monitors" "h_tiles" "prev" "window-force-center" "trigger-binding" "-h" "move-node-to-workspace" "wrap-around-the-workspace" "enable" "--ignore-floating" "--visible" "close-all-windows-but-current" "--help" "--macos-native-hidden" "off" "move-workspace-to-monitor" "--boundaries" "set" "workspace-back-and-forth" "--quit-if-last-window" "window-lazy-center" "workspace" "--major-keys" "accordion" "--focused" "tiling" "--app-bundle-id" "--mouse" "balance-sizes" "opposite" "sticky" "on" "--auto-back-and-forth" "--version" "--json" "join-with" "reload-config" "--workspace" "floating" "--swap-focus" "--mode" "--boundaries-action" "resize" "visible" "close" "up" "layout" "--fail-if-noop" "--tree" "fail" "list-exec-env-vars" "--focus-follows-window" "split" "--monitor" "--pid" "mute-on" "v_tiles" "monitor-lazy-center" "--keys" "wrap-around-all-monitors" "--wrap-around" "horizontal" "create-implicit-container" "config" "--no-outer-gaps" "focused" "mute-off" "--all-keys" "--show-secrets" "--all" "left" "right" "swap" "--config-path" "--get" "tiles" "--no-gui" "dfs-next" "smart-opposite" "--format" "list-modes" "--empty" "--dry-run" "move-node-to-monitor" "dfs-prev" "move" "focus" "down" "list-workspaces" "volume" "no" "stop" "debug-windows" "macos-native-minimize" "list-windows" "mouse" "next" "--dfs-index" "open-settings" "fullscreen" "focus-monitor" "--current" "v_accordion" "vertical"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 3 55 56 35 5 38 62 92 64 100 14 41 66 70 15 103 72 20 16 19 105 106 18 24 25 108 26 109 112 113 114 28 48 83 50 118 31 53 119 32 120; set tos 122 16 128 94 129 65 16 69 5 130 107 95 114 131 15 6 72 82 79 132 16 35 106 125 57 16 133 134 104 19 83 86 135 6 116 65 16 85 16 24 16 108"
    set literal_transitions[2] "set inputs 11 115 85; set tos 3 3 3"
    set literal_transitions[3] "set inputs 11 2 74 115 57 99 73 46 54 85; set tos 3 51 52 3 54 55 2 53 51 3"
    set literal_transitions[5] "set inputs 107 12 97 59 65 90 91 80 104; set tos 119 4 119 5 119 119 119 5 119"
    set literal_transitions[6] "set inputs 57; set tos 7"
    set literal_transitions[8] "set inputs 111 27 69 79; set tos 9 9 9 9"
    set literal_transitions[9] "set inputs 36 61 90 91 107 29 65; set tos 56 8 10 10 10 9 10"
    set literal_transitions[10] "set inputs 36 61 29; set tos 11 12 10"
    set literal_transitions[11] "set inputs 9 41; set tos 10 10"
    set literal_transitions[12] "set inputs 111 27 69 79; set tos 10 10 10 10"
    set literal_transitions[15] "set inputs 88; set tos 16"
    set literal_transitions[18] "set inputs 116 57 22 107 65 90 91 80; set tos 49 92 49 49 49 49 49 93"
    set literal_transitions[19] "set inputs 12 68; set tos 20 16"
    set literal_transitions[21] "set inputs 30 2 110 101 99 54; set tos 21 22 22 21 23 22"
    set literal_transitions[22] "set inputs 30 2 101 99 54; set tos 21 22 21 23 22"
    set literal_transitions[24] "set inputs 84 67 12 34 51; set tos 25 26 27 28 29"
    set literal_transitions[25] "set inputs 84 67 12 51; set tos 25 105 103 29"
    set literal_transitions[26] "set inputs 84 67 12 34 51; set tos 105 105 136 28 29"
    set literal_transitions[28] "set inputs 12 67; set tos 20 16"
    set literal_transitions[29] "set inputs 12 84 67; set tos 121 29 29"
    set literal_transitions[30] "set inputs 54 78; set tos 30 30"
    set literal_transitions[32] "set inputs 12 36 61; set tos 31 123 33"
    set literal_transitions[33] "set inputs 69 82 111; set tos 32 32 32"
    set literal_transitions[34] "set inputs 9 41; set tos 35 35"
    set literal_transitions[35] "set inputs 36 61 90 91 12 107 65; set tos 34 45 32 32 142 32 32"
    set literal_transitions[36] "set inputs 12 67 71; set tos 37 36 36"
    set literal_transitions[38] "set inputs 11 115 85; set tos 39 39 39"
    set literal_transitions[39] "set inputs 11 2 115 101 99 30 54 85; set tos 39 22 39 21 23 21 22 39"
    set literal_transitions[40] "set inputs 77 40 13 23; set tos 41 41 41 41"
    set literal_transitions[41] "set inputs 67; set tos 16"
    set literal_transitions[42] "set inputs 10 21 58 81 95 45 76 43 122 123; set tos 42 42 42 42 42 42 42 42 42 42"
    set literal_transitions[43] "set inputs 52 67; set tos 43 43"
    set literal_transitions[44] "set inputs 52 67; set tos 44 44"
    set literal_transitions[45] "set inputs 69 82 111; set tos 35 35 35"
    set literal_transitions[46] "set inputs 67 12 71; set tos 36 37 36"
    set literal_transitions[48] "set inputs 116 12 22 107 65 90 91 80 71; set tos 73 47 73 73 73 73 73 48 48"
    set literal_transitions[49] "set inputs 57 80; set tos 50 49"
    set literal_transitions[51] "set inputs 74 2 46 57 54 73 99; set tos 52 51 53 54 51 2 55"
    set literal_transitions[54] "set inputs 85 63; set tos 78 78"
    set literal_transitions[56] "set inputs 9 41; set tos 9 9"
    set literal_transitions[57] "set inputs 60; set tos 13"
    set literal_transitions[58] "set inputs 60; set tos 132"
    set literal_transitions[59] "set inputs 67 12 34 51; set tos 60 61 62 62"
    set literal_transitions[60] "set inputs 67 12 34 51; set tos 60 61 62 62"
    set literal_transitions[62] "set inputs 12 67; set tos 140 62"
    set literal_transitions[63] "set inputs 116 22 80 71; set tos 64 64 63 63"
    set literal_transitions[64] "set inputs 80 71; set tos 64 64"
    set literal_transitions[65] "set inputs 67 12 34 51; set tos 60 66 62 62"
    set literal_transitions[67] "set inputs 67 12 71; set tos 67 68 67"
    set literal_transitions[69] "set inputs 17 4 7 12 98; set tos 70 70 70 71 70"
    set literal_transitions[72] "set inputs 116 12 22 107 65 90 91 67 80 71; set tos 73 74 73 73 73 73 73 67 48 72"
    set literal_transitions[73] "set inputs 12 80 71; set tos 90 73 73"
    set literal_transitions[75] "set inputs 67 12 71; set tos 75 76 75"
    set literal_transitions[78] "set inputs 74 2 63 57 99 46 54 85 73; set tos 52 51 78 54 55 53 51 78 2"
    set literal_transitions[79] "set inputs 2 99 54 47 44; set tos 79 80 79 81 81"
    set literal_transitions[81] "set inputs 110 2 99 54 47 44; set tos 79 79 80 79 81 81"
    set literal_transitions[82] "set inputs 49 12 81 123; set tos 83 84 83 83"
    set literal_transitions[83] "set inputs 12; set tos 20"
    set literal_transitions[85] "set inputs 39; set tos 16"
    set literal_transitions[86] "set inputs 74 2 57 99 44 89 46 54 73; set tos 52 87 54 88 89 89 53 87 2"
    set literal_transitions[87] "set inputs 74 2 57 99 44 89 46 54 73; set tos 52 51 54 55 89 89 53 51 2"
    set literal_transitions[89] "set inputs 99 2 54; set tos 91 16 16"
    set literal_transitions[93] "set inputs 116 107 57 22 65 90 91 80; set tos 49 49 92 49 49 49 49 93"
    set literal_transitions[94] "set inputs 96 102; set tos 94 94"
    set literal_transitions[95] "set inputs 2 99 54 33; set tos 95 96 95 97"
    set literal_transitions[97] "set inputs 110 2 99 54 33; set tos 95 95 96 95 97"
    set literal_transitions[98] "set inputs 17 4 7 98; set tos 70 70 70 70"
    set literal_transitions[99] "set inputs 2 101 99 44 30 89 54 73; set tos 100 101 102 89 101 89 100 38"
    set literal_transitions[100] "set inputs 30 2 101 99 54 73; set tos 101 100 101 102 100 38"
    set literal_transitions[101] "set inputs 30 2 110 101 99 54 73; set tos 101 100 100 101 102 100 38"
    set literal_transitions[104] "set inputs 65 37 6 75 107 86; set tos 16 91 16 16 16 16"
    set literal_transitions[105] "set inputs 84 67 12 51; set tos 105 105 136 29"
    set literal_transitions[106] "set inputs 12 107 29 65 36 61 90 91 117; set tos 20 10 9 10 56 8 10 10 91"
    set literal_transitions[107] "set inputs 121; set tos 16"
    set literal_transitions[108] "set inputs 116 107 22 65 90 91 80; set tos 110 110 110 110 110 110 111"
    set literal_transitions[110] "set inputs 80; set tos 16"
    set literal_transitions[111] "set inputs 90 91 116 107 22 65; set tos 110 110 110 110 110 110"
    set literal_transitions[113] "set inputs 10 21 58 81 95 45 76 43 122 123; set tos 42 42 42 42 42 42 42 42 42 42"
    set literal_transitions[114] "set inputs 52 67 116 22 80; set tos 43 43 110 110 115"
    set literal_transitions[115] "set inputs 22 116; set tos 110 110"
    set literal_transitions[116] "set inputs 87 42 78 54 94 93; set tos 16 16 117 117 118 16"
    set literal_transitions[117] "set inputs 54 94 78; set tos 117 118 117"
    set literal_transitions[119] "set inputs 12 59 80; set tos 120 119 119"
    set literal_transitions[122] "set inputs 67 40 13 23 77; set tos 40 41 41 41 41"
    set literal_transitions[123] "set inputs 9 41; set tos 32 32"
    set literal_transitions[124] "set inputs 81 123 49; set tos 83 83 83"
    set literal_transitions[125] "set inputs 67; set tos 77"
    set literal_transitions[127] "set inputs 90 91 107 65; set tos 16 16 16 16"
    set literal_transitions[128] "set inputs 90 91 12 107 65; set tos 16 16 126 16 16"
    set literal_transitions[129] "set inputs 116 57 22 107 65 90 91 80; set tos 49 17 49 49 49 49 49 93"
    set literal_transitions[130] "set inputs 12 39; set tos 139 130"
    set literal_transitions[131] "set inputs 10 95 12 21 58 81 45 76 43 122 123; set tos 42 42 112 42 42 42 42 42 42 42 42"
    set literal_transitions[133] "set inputs 2 101 99 44 30 89 54 73; set tos 99 101 138 89 101 89 99 38"
    set literal_transitions[134] "set inputs 71 67 116 12 80 22; set tos 134 75 64 76 63 64"
    set literal_transitions[135] "set inputs 67 34 8 51; set tos 143 41 16 41"
    set literal_transitions[137] "set inputs 57; set tos 7"
    set literal_transitions[141] "set inputs 84 67 12 34 51; set tos 25 105 103 28 29"
    set literal_transitions[143] "set inputs 34 51; set tos 41 41"

    set --local match_anything_transitions_from 7 76 54 112 37 125 66 96 88 136 47 80 46 142 43 14 68 20 114 31 108 103 118 38 140 139 132 129 55 109 53 50 3 39 61 138 137 77 2 126 91 67 4 72 92 102 52 71 27 120 18 84 121 75 74 134 78 90 23 57 13 17
    set --local match_anything_transitions_to 16 75 78 113 36 41 59 95 87 105 48 79 46 35 44 16 67 16 44 32 109 25 30 39 62 130 16 137 51 109 51 49 3 39 60 99 137 41 3 127 16 46 5 46 93 100 51 98 141 119 137 124 29 36 72 36 78 73 22 58 14 18
    set subword_transitions[70] "set subword_ids 1; set tos 83"

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

    set command_states 7 76 54 112 129 55 109 53 50 3 39 61 138 137 37 77 125 2 126 66 96 88 91 136 67 4 47 72 80 92 102 52 71 27 46 120 18 84 142 43 121 14 75 74 134 78 90 23 20 68 57 13 114 31 108 17 103 118 38 140 139 132
    set command_ids 62 58 62 58 59 59 59 31 62 39 39 58 59 59 58 62 62 39 58 58 59 59 59 58 59 58 58 59 59 62 59 47 58 58 59 58 59 58 58 62 58 60 62 58 62 62 58 59 58 58 60 61 62 58 59 62 58 23 39 58 58 61
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
