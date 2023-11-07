import info.debatty.java.stringsimilarity.Damerau
import java.io.File
import kotlin.math.max

fun main(args: Array<String>) {
    val maxScore = 0.4
    val damerau = Damerau()

    val baseDir = File("src/test/resources")
    val words = File(baseDir, "words.txt")
        .bufferedReader()
        .lineSequence()
        .map { it.split("\t")[0] }
        .toList()
        .distinct()
    println("Loaded ${words.size} words")

    val startTime = System.currentTimeMillis()

    class Score(val first: String, val second: String, val distance: Double) {
        val str by lazy {
            "$first $second $distance"
        }

        override fun toString() = str
    }

    val matrix = words.indices
        .flatMap { i ->
            (i + 1..<words.size)
                .map { j ->
                    Score(
                        words[i], words[j],
                        damerau.distance(words[i], words[j]) /
                                max(words[i].length, words[j].length).toDouble()
                    )
                }
                .filter { it.distance < maxScore }
                .flatMap {
                    listOf(
                        it,
                        Score(it.second, it.first, it.distance)
                    )
                }
        }
        .groupBy { it.first }
        .mapValues { (word, values) ->
            values.associate { it.second to it.distance } + (word to 0.0)
        }

    File(baseDir, "word-matrix.txt").printWriter().use { out ->
        matrix
            .toList()
            .sortedBy { it.first }
            .forEach { (word, neighbors) ->
                val neighborStr = neighbors
                    .toList()
                    .sortedBy { (_, s) -> s }
                    .joinToString(" ") { (w, s) -> "$w:$s" }
                out.println("$word $neighborStr")
            }
        out.flush()
    }

    val endTime = System.currentTimeMillis()
    println("Wrote ${matrix.size} scores in ${endTime - startTime} milliseconds")

    fun intraDistances(cluster: Collection<String>): List<Pair<String, Double>> =
        cluster
            .map { first ->
                first to cluster
                    .map { second ->
                        matrix[first]!![second]!!
                    }
                    .average()
            }
            .sortedBy { it.second }

    fun analyzeCluster(cluster: Collection<String>): Triple<List<String>, List<String>, Double> =
        intraDistances(cluster)
            .let { intraDistances ->
                val bestIntraDistance = intraDistances.first().second
                val medoids = intraDistances
                    .takeWhile { it.second == bestIntraDistance }
                    .map { it.first }
                    .sorted()
                val avgIntraDistance = intraDistances.map { it.second }.average()
                val orderedCluster = intraDistances.sortedBy { it.second }.map { it.first }
                Triple(orderedCluster, medoids, avgIntraDistance)
            }

    class DistanceClusters(
        distance: Double,
        orderedCluster: List<String>,
        intraDistance: Double,
        medoids: List<String>,
        others: List<String>
    ) {
        val str by lazy {
            listOf(
                distance,
                intraDistance,
                medoids.size,
                medoids.joinToString(","),
                orderedCluster.size,
                orderedCluster.joinToString(","),
                others.size,
                others.joinToString(","),
            )
                .joinToString(" ")
        }

        override fun toString() = str
    }

    val distances = matrix.values
        .flatMap { it.values.toSet() }
        .toSet().toList().sorted()

    val distanceClusters = distances
        .filter { it > 0.0 }
        .map { threshold ->
            threshold to matrix
                .map { (word, neighbors) ->
                    word to neighbors
                        .filter { (_, distance) -> distance <= threshold }
                        .map { it.key }
                        .toSet()
                }
                .groupBy { (_, profile) -> profile }
                .toList()
                .map { (profile, values) ->
                    values.map { it.first }.toSet() to profile
                }
                .sortedBy { -it.first.size }
        }
        .flatMap { (distance, pairs) ->
            pairs
                .map { (cluster, profile) ->
                    val others = profile.minus(cluster).sorted()
                    val (orderedCluster, medoids, intraDistance) =
                        analyzeCluster(cluster)
                    DistanceClusters(distance, orderedCluster, intraDistance, medoids, others)
                }
        }
    File(baseDir, "word-distance-clusters.txt").printWriter().use { out ->
        distanceClusters.forEach(out::println)
        out.flush()
    }
}