// Case 1 — The clever SQL query
// The developer tries to solve everything in one query using nested subqueries, window functions, correlated conditions, and calculations inside calculations.


SELECT
    DATE_TRUNC('MONTH', x.event_date) AS event_month,
    x.student_id,

    MAX(IFF(
        x.balance <= 0
        AND x.lessons_used > 0
        AND NOT EXISTS (
            SELECT 1
            FROM lesson p
            WHERE p.student_id = x.student_id
              AND p.created_at > x.event_date
              AND p.created_at <= DATEADD('DAY', 8, x.event_date)
              AND p.type != 'unpaid'
        )
        AND x.event_date <= DATEADD('DAY', -8, :as_of_date),
        1, 0
    )) AS is_churn,

    MAX(IFF(
        x.balance > 0
        AND DATEDIFF(
            'DAY',
            x.last_lesson_date,
            :as_of_date
        ) > 30,
        1, 0
    )) AS is_sleeping

FROM (
    SELECT
        e.*,

        SUM(
            e.lessons_paid - e.lessons_used
        ) OVER (
            PARTITION BY e.student_id
            ORDER BY e.event_date
            ROWS UNBOUNDED PRECEDING
        ) AS balance,

        MAX(IFF(e.lessons_used > 0, e.event_date, NULL))
            OVER (
                PARTITION BY e.student_id
                ORDER BY e.event_date
                ROWS UNBOUNDED PRECEDING
            ) AS last_lesson_date

    FROM (
        SELECT
            student_id,
            event_date,
            SUM(lessons_paid) AS lessons_paid,
            SUM(lessons_used) AS lessons_used

        FROM (
            SELECT
                student_id,
                CAST(created_at AS DATE) AS event_date,
                number_of_lessons AS lessons_paid,
                0 AS lessons_used
            FROM lesson
            WHERE type != 'unpaid'

            UNION ALL

            SELECT
                student AS student_id,
                CAST(datetime AS DATE) AS event_date,
                0 AS lessons_paid,
                IFF(
                    status = 4
                    AND datetime >= '2022-12-01'
                    AND datetime < '2023-03-01',
                    0, 1
                ) AS lessons_used
            FROM passed
            WHERE status IN (2, 4)
              AND type != 'trial'
        ) raw_events
        GROUP BY 1, 2
    ) e
) x

GROUP BY 1, 2;
