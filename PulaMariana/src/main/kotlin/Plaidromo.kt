import java.io.IO.println

fun palandrino(palavra: String): Boolean{

    var begin = 0
    var end = palavra.length - 1;

    while (begin < end){
        if(palavra[begin]!=palavra[end]){
            return false;
        }
        end--;
        begin++;
    }
    return true;
}

fun main() {
    println(palandrino("ana"))
}
