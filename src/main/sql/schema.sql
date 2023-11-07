-- \i words.sql

CREATE TABLE scores AS
SELECT first,
       second,
       distance,
       distance /
       CAST(GREATEST(LENGTH(first), LENGTH(second)) AS REAL) AS length_normalized_distance,
       0.0                                                   AS simple_normalized_distance
FROM (SELECT w1.word                       AS first,
             w2.word                       AS second,
             LEVENSHTEIN(w1.word, w2.word) AS distance
      FROM words AS w1
               JOIN words AS w2 ON w2.word > w1.word) AS t;

INSERT INTO scores(first, second, distance, simple_normalized_distance, length_normalized_distance)
SELECT second, first, distance, simple_normalized_distance, length_normalized_distance
FROM scores;

INSERT INTO scores(first, second, distance, simple_normalized_distance, length_normalized_distance)
SELECT word, word, 0, 0.0, 0.0
FROM words;

CREATE TABLE distance_stats AS
SELECT CAST(COUNT(DISTINCT distance) AS REAL)        AS count_distance,
       CAST(MIN(distance) AS REAL)                   AS min_distance,
       CAST(MAX(distance) AS REAL)                   AS max_distance,
       AVG(distance)                                 AS avg_distance,
       STDDEV(distance)                              AS stddev_distance,
       COUNT(DISTINCT length_normalized_distance)    AS count_length_normalized_distance,
       CAST(MIN(length_normalized_distance) AS REAL) AS min_length_normalized_distance,
       CAST(MAX(length_normalized_distance) AS REAL) AS max_length_normalized_distance,
       AVG(length_normalized_distance)               AS avg_length_normalized_distance,
       STDDEV(length_normalized_distance)            AS stddev_length_normalized_distance
FROM scores;

UPDATE scores
SET simple_normalized_distance = (SELECT (max_distance - distance) / (max_distance - min_distance) FROM distance_stats);

ALTER TABLE distance_stats
    ADD COLUMN count_simple_normalized_distance REAL;
ALTER TABLE distance_stats
    ADD COLUMN min_simple_normalized_distance REAL;
ALTER TABLE distance_stats
    ADD COLUMN max_simple_normalized_distance REAL;
ALTER TABLE distance_stats
    ADD COLUMN avg_simple_normalized_distance REAL;
ALTER TABLE distance_stats
    ADD COLUMN stddev_simple_normalized_distance REAL;
UPDATE distance_stats
SET (count_simple_normalized_distance, min_simple_normalized_distance, max_simple_normalized_distance,
     avg_simple_normalized_distance,
     stddev_simple_normalized_distance) = (SELECT COUNT(DISTINCT simple_normalized_distance)    AS count_length_normalized,
                                                  CAST(MIN(simple_normalized_distance) AS REAL) AS min_length_normalized,
                                                  CAST(MAX(simple_normalized_distance) AS REAL) AS max_length_normalized,
                                                  AVG(simple_normalized_distance)               AS avg_length_normalized,
                                                  STDDEV(simple_normalized_distance)            AS stddev_length_normalized
                                           FROM scores);

CREATE UNIQUE INDEX scores_uk ON scores (first, second);
CREATE INDEX scores_distance ON scores (distance);

CREATE TABLE distances AS
SELECT length_normalized_distance                                          AS distance,
       COUNT(*) / CASE length_normalized_distance WHEN 0 THEN 1 ELSE 2 END AS count
FROM scores AS s
GROUP BY length_normalized_distance
ORDER BY length_normalized_distance;

CREATE TABLE scores_by_distance AS
SELECT d.distance                   AS max_distance,
       s.first,
       s.second,
       s.length_normalized_distance AS distance
FROM distances AS d,
     scores AS s
WHERE d.distance IN (SELECT distance
                     FROM distances
                     WHERE distance BETWEEN 0.3 AND 0.4)
  AND s.length_normalized_distance <= d.distance
ORDER BY d.distance, s.first, s.second;

CREATE TABLE profiles_by_distance AS
SELECT max_distance                      AS distance,
       first                             AS word,
       ARRAY_AGG(second ORDER BY second) AS profile
FROM scores_by_distance s
GROUP BY max_distance, first
ORDER BY max_distance, first;

CREATE TYPE cluster_element AS
(
    word       VARCHAR,
    distance   REAL,
    word_count INTEGER
);

ALTER TABLE profiles_by_distance
    ADD COLUMN profile_cluster cluster_element[];

UPDATE profiles_by_distance p
SET profile_cluster = ARRAY(SELECT CAST(ROW (first.word, AVG(scores.length_normalized_distance), words.count) AS cluster_element)
                            FROM (SELECT unnest(profile) AS word) AS first,
                                 (SELECT unnest(profile) AS word) AS second,
                                 scores,
                                 words
                            WHERE scores.first = first.word
                              AND scores.second = second.word
                              AND words.word = first.word
                            GROUP BY first.word, words.count
                            ORDER BY AVG(scores.length_normalized_distance), words.count DESC, first.word);

ALTER TABLE profiles_by_distance
    ADD COLUMN profile_medoids VARCHAR[];

UPDATE profiles_by_distance p
SET profile_medoids = ARRAY(
        SELECT (t.cluster_element).word
        FROM (SELECT UNNEST(profile_cluster) AS cluster_element) AS t
        WHERE (t.cluster_element).distance = (p.profile_cluster[1]).distance
        ORDER BY 1);

CREATE TABLE clusters_by_distance AS
SELECT distance, profile_medoids, ARRAY_AGG(word) AS cluster
FROM profiles_by_distance
GROUP BY distance, profile_medoids
ORDER BY distance, ARRAY_LENGTH(ARRAY_AGG(word), 1) DESC;



ALTER TABLE clusters_by_distance
    ADD COLUMN cluster_elements cluster_element[];
UPDATE clusters_by_distance
SET cluster_elements = ARRAY(SELECT CAST(ROW (first.word, AVG(scores.length_normalized_distance), words.count) AS cluster_element)
                             FROM (SELECT unnest(cluster) AS word) AS first,
                                  (SELECT unnest(cluster) AS word) AS second,
                                  scores,
                                  words
                             WHERE scores.first = first.word
                               AND scores.second = second.word
                               AND words.word = first.word
                             GROUP BY first.word, words.count
                             ORDER BY AVG(scores.length_normalized_distance), words.count DESC, first.word);

ALTER TABLE clusters_by_distance
    ADD COLUMN cluster_medoids VARCHAR[];
UPDATE clusters_by_distance c
SET cluster_medoids = ARRAY(
        SELECT (t.cluster_element).word
        FROM (SELECT UNNEST(cluster_elements) AS cluster_element) AS t
        WHERE (t.cluster_element).distance = (c.cluster_elements[1]).distance
        ORDER BY 1);