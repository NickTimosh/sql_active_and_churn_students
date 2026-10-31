// Case 2 — Clean SQL with CTEs
// Now we separate each transformation into a clearly named step. This is inspired by your original implementation, with a few simplifications.


WITH payments AS (

    SELECT
        student_id,
        CAST(created_at AS DATE) AS event_date,
        SUM(number_of_lessons) AS lessons_paid
    FROM lesson
    WHERE type != 'unpaid'
    GROUP BY 1, 2

),

completed_lessons AS (

    SELECT
        student AS student_id,
        CAST(datetime AS DATE) AS event_date,
        COUNT_IF(
            NOT (
                status = 4
                AND datetime >= '2022-12-01'
                AND datetime < '2023-03-01'
            )
        ) AS lessons_used
    FROM passed
    WHERE status IN (2, 4)
      AND type != 'trial'
    GROUP BY 1, 2

),

student_events AS (

    SELECT
        COALESCE(p.student_id, l.student_id) AS student_id,
        COALESCE(p.event_date, l.event_date) AS event_date,
        COALESCE(p.lessons_paid, 0) AS lessons_paid,
        COALESCE(l.lessons_used, 0) AS lessons_used
    FROM payments p
    FULL OUTER JOIN completed_lessons l
        ON p.student_id = l.student_id
       AND p.event_date = l.event_date

),

student_balances AS (

    SELECT
        *,
        SUM(lessons_paid - lessons_used) OVER (
            PARTITION BY student_id
            ORDER BY event_date
            ROWS UNBOUNDED PRECEDING
        ) AS balance,

        MAX(IFF(lessons_used > 0, event_date, NULL))
            OVER (
                PARTITION BY student_id
                ORDER BY event_date
                ROWS UNBOUNDED PRECEDING
            ) AS last_lesson_date
    FROM student_events

),

student_churn AS (

    SELECT
        b.*,

        IFF(
            balance <= 0
            AND lessons_used > 0
            AND event_date <= DATEADD('DAY', -8, :as_of_date)
            AND NOT EXISTS (
                SELECT 1
                FROM payments p
                WHERE p.student_id = b.student_id
                  AND p.event_date > b.event_date
                  AND p.event_date <= DATEADD('DAY', 8, b.event_date)
            ),
            1, 0
        ) AS is_churn,

        IFF(
            balance > 0
            AND DATEDIFF(
                'DAY', last_lesson_date, :as_of_date
            ) > 30,
            1, 0
        ) AS is_sleeping

    FROM student_balances b
    WHERE event_date <= :as_of_date

)

SELECT
    DATE_TRUNC('MONTH', event_date) AS event_month,
    student_id,
    MAX(is_churn) AS is_churn,
    MAX(is_sleeping) AS is_sleeping
FROM student_churn
GROUP BY 1, 2;
