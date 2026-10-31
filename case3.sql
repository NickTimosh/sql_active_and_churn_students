// Case 3 — Data modeling: Bronze → Silver → Gold
// Instead of writing one large query, we build a data platform in which each transformation has a specific responsibility.

-- Example A — Silver: standardize events: stg_lesson_transactions.sql

SELECT
    id AS transaction_id,
    student_id,
    CAST(created_at AS DATE) AS transaction_date,
    number_of_lessons AS credits_added,
    type AS transaction_type
FROM {{ source('app', 'lesson') }}
WHERE type != 'unpaid'

-- Example B — Gold: create a reusable fact: fct_lesson_transactions.sql


SELECT
    transaction_id,
    student_id,
    transaction_date,
    credits_added,
    transaction_type
FROM {{ ref('stg_lesson_transactions') }}

-- Example C — Gold: create a student balance model: fct_student_daily_balance.sql


WITH daily_events AS (

    SELECT
        student_id,
        transaction_date AS event_date,
        SUM(credits_added) AS credits_added,
        0 AS credits_used
    FROM {{ ref('fct_lesson_transactions') }}
    GROUP BY 1, 2

    UNION ALL

    SELECT
        student_id,
        lesson_date AS event_date,
        0 AS credits_added,
        SUM(credits_used) AS credits_used
    FROM {{ ref('fct_student_activity') }}
    GROUP BY 1, 2

),

daily_totals AS (

    SELECT
        student_id,
        event_date,
        SUM(credits_added) AS credits_added,
        SUM(credits_used) AS credits_used
    FROM daily_events
    GROUP BY 1, 2

)

SELECT
    student_id,
    event_date,
    credits_added,
    credits_used,
    SUM(credits_added - credits_used) OVER (
        PARTITION BY student_id
        ORDER BY event_date
        ROWS UNBOUNDED PRECEDING
    ) AS balance
FROM daily_totals

-- Example D — Gold: create the churn mart: mart_student_churn.sql


WITH student_status AS (

    SELECT
        b.student_id,
        b.event_date,
        b.balance,
        b.credits_used,

        a.last_lesson_date,
        p.next_payment_date

    FROM {{ ref('fct_student_daily_balance') }} b

    LEFT JOIN {{ ref('int_student_activity_timeline') }} a
        ON b.student_id = a.student_id
       AND b.event_date = a.event_date

    LEFT JOIN {{ ref('int_student_payment_timeline') }} p
        ON b.student_id = p.student_id
       AND b.event_date = p.event_date

),

churn_flags AS (

    SELECT
        *,
        IFF(
            balance <= 0
            AND credits_used > 0
            AND event_date <= DATEADD('DAY', -8, :as_of_date)
            AND (
                next_payment_date IS NULL
                OR next_payment_date > DATEADD('DAY', 8, event_date)
            ),
            1, 0
        ) AS is_churn,

        IFF(
            balance > 0
            AND DATEDIFF('DAY', last_lesson_date, :as_of_date) > 30,
            1, 0
        ) AS is_sleeping
    FROM student_status
    WHERE event_date <= :as_of_date

)

SELECT *
FROM churn_flags;
