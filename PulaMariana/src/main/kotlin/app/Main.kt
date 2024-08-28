package app

val numberToName = mapOf(
    1 to "um",
    2 to "dois",
    3 to "três",
    4 to "quatro",
    5 to "cinco",
    6 to "seis",
    7 to "sete",
    8 to "oito",
    9 to "nove",
    10 to "dez"
)

fun pulaMarina(count: Int){
    (1 .. count).forEach { i ->
        println("Mariana conta ${numberToName[i]} ")
        print("Mariana conta é ${numberToName[i]} ")
        (1 until i).forEach { _ ->
             print("é ${numberToName[i]} ")
        }
        println()
        println("Ana, viva a Mariana, viva a Mariana")
        println()
    }
}

fun main() {
    println()
    pulaMarina(10)
}