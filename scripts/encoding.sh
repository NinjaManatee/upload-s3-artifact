# Script with functions for URL encoding/decoding a string
# see: https://gist.github.com/cdown/1163649#file-gistfile1-sh

urlencode() {
    # urlencode <string>

    # save current LC_COLLATE for restoring
    local old_lc_collate=$LC_COLLATE

    # setting LC_COLLATE=C forces a case-sensitive sort, where 'A' comes before 'a'.
    LC_COLLATE=C

    # get the length of first argument
    local length="${#1}"

    local i
    for ((i = 0; i < length; i++)); do
        # get the ith character from the input
        local c="${1:$i:1}"

        # print character if it doesn't need to be encoded, encode character if it does
        case $c in
        [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
        *) printf '%%%02X' "'$c" ;;
        esac
    done

    # restore original LC_COLLATE
    LC_COLLATE=$old_lc_collate
}

urldecode() {
    # urldecode <string>

    local url_encoded="${1//+/ }"
    printf "%b" "${url_encoded//%/\\x}"
}
