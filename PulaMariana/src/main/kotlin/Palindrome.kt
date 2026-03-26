fun palindrome(word: String): Boolean{

    var begin = 0
    var end = word.length - 1

    while (begin < end){
        if(word[begin]!=word[end]){
            return false
        }
        end--
        begin++
    }
    return true
}

fun main() {
    println(palindrome("ana"))
}
