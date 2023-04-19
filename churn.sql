# 1. Scheduled students (regular and single lessons)

WITH all_dates AS (

    SELECT DISTINCT DATE_FORMAT(datetime, '%Y-%m-01') AS event_month
    FROM calendar
    WHERE datetime IS NOT NULL
)

, regular_lessons AS (
      SELECT  startFrom           AS startFrom
              , deleted_at        AS deleted_at        	              
              , cs.student_id     AS student_id
      FROM calendar AS cl
        LEFT JOIN classroom AS cs ON cl.classroom = cs.classroom_id
      WHERE cl.type IN ('regular')
)

, schedule AS (   -- appending single and regular students

      # all distinct single_students for each month

      SELECT s.event_month      
            , s.student_id
            , 1 as in_sc
      FROM ( -- single_students
              SELECT  DATE_FORMAT(datetime, '%Y-%m-01')   AS event_month
                      , cs.student_id                     AS student_id
              FROM calendar AS cl
                LEFT JOIN classroom AS cs ON cl.classroom = cs.classroom_id
              WHERE cl.type IN ('single', 'trial')
                -- the day of each month where scheduled students considered as active:
                # AND created_at <= DATE_FORMAT(datetime, '%Y-%m-08')  
                # AND (deleted_at IS NULL OR deleted_at > DATE_FORMAT(datetime, '%Y-%m-08'))
                AND (deleted_at IS NULL OR deleted_at > DATE_FORMAT(datetime, '%Y-%m-01'))
            ) AS s
      WHERE 1=1
      GROUP BY 1,2

      UNION

      # all distinct regular_students for each month

      SELECT ad.event_month
            , r.student_id
            , 1 as in_sc
      FROM all_dates AS ad
        LEFT JOIN regular_lessons AS r
          ON (ad.event_month >= r.startFrom)
            AND (ad.event_month <= r.deleted_at)
      WHERE 1=1
      GROUP BY 1,2
)

#2. Dinamic Balance for each student

, event_day AS ( -- calendar for all events (all payments and all lessons visits)

      SELECT DATE_FORMAT(datetime, '%Y-%m-%d')    AS event_day
            , student                             AS student_id
      FROM passed    -- all completed lessons 
      WHERE 1=1
        AND status IN (2,4) -- visits and missed lessons
        AND type != 'trial'

      UNION

      SELECT DATE_FORMAT(created_at, '%Y-%m-%d')  AS event_day
            , student_id                          AS student_id
      FROM lesson    -- all lessons purchased,bonused and transfered
      WHERE type != 'unpaid'
)

, paid_lesson AS (

    SELECT DATE_FORMAT(created_at, '%Y-%m-%d')    AS event_day_paid
          , student_id                            AS student_id
          , 1                                     AS paid_flag
          , type                                  AS lesson_paid_type
          , number_of_lessons                     AS nmb_lessons_paid
          , FIRST_VALUE(created_at) OVER(PARTITION BY student_id ORDER BY created_at ASC) AS first_payment_date
          , LEAD(created_at, 1) OVER(PARTITION BY student_id ORDER BY created_at ASC) AS next_payment_date 
    FROM lesson
    WHERE type != 'unpaid'
)

, passed_lesson AS (

    SELECT DATE_FORMAT(ps.datetime, '%Y-%m-%d') 	  AS event_day_passed
          , ps.student		                          AS student_id
          , ps.status                               AS lesson_status
          , LEAD(ps.datetime, 1) OVER(PARTITION BY ps.student ORDER BY ps.datetime ASC) AS next_lesson_date
          
          -- additional conditions:
 
          , CASE WHEN 
                  -- missed lessons in given period are not considered due to the lockdown:
                      (DATE_FORMAT(ps.datetime, '%Y-%m-%d') BETWEEN '2022-12-01' AND '2023-02-28'
                      AND ps.status IN (4))
                      OR
                  -- lessons passed before first_payment_date:
                      ps.datetime < pd.first_payment_date
                  THEN 0 ELSE 1 END             AS lesson_flag

    FROM passed AS ps
      LEFT JOIN (SELECT student_id, first_payment_date FROM paid GROUP BY 1) AS pd ON ps.student = pd.student_id
    WHERE 1=1
      AND ps.status IN (2,4)
      AND ps.type != 'trial'
      AND ps.id IS NOT NULL
        -- include only students who have any payments/bonuses or transferring
      AND ps.student IN (
                        SELECT student_id
                        FROM paid
                        GROUP BY 1
                        HAVING MAX(paid_flag) = 1
                      )       
)

, balances AS (
    
    SELECT ed.* -- all event_days and students
          , COALESCE(ps.lesson_flag,0)                                                                                                      AS lesson_flag
          , COALESCE(ps.lesson_status,0)                                                                                                    AS lesson_status
          , COALESCE(pd.paid_flag,0)                                                                                                        AS paid_flag
          , COALESCE(pd.nmb_lessons_paid,0)                                                                                                 AS lessons_paid
          , pd.lesson_paid_type                                                                                                             AS lesson_paid_type
          , SUM(COALESCE(pd.nmb_lessons_paid,0)  - COALESCE(ps.lesson_flag,0)) OVER (PARTITION BY ed.student_id ORDER by ed.event_day ASC)  AS cum_balance
          , DATE_FORMAT(pd.next_payment_date, '%Y-%m-%d')	                                                                                  AS next_payment_date
          , DATEDIFF(pd.next_payment_date, ed.event_day)                                                                                    AS days_between_payments
          , DATE_FORMAT(ps.next_lesson_date, '%Y-%m-%d')	                                                                                  AS next_lesson_date
          , DATEDIFF(ps.next_lesson_date, ed.event_day)                                                                                     AS days_between_lessons
    FROM event_day AS ed
      LEFT JOIN passed AS ps ON ed.event_day = ps.event_day_passed AND ed.student_id = ps.student_id
      LEFT JOIN paid AS pd ON ed.event_day = pd.event_day_paid AND ed.student_id = pd.student_id
      LEFT JOIN app AS a ON ed.student_id = a.id
    WHERE (a.email NOT LIKE '%test%')     -- excluding test accounts
)

, days AS (

    SELECT DATE_FORMAT(b.event_day, '%Y-%m-01') AS event_month
          , b.event_day
          , b.student_id
          , b.lesson_flag
          , b.lesson_status
          , b.paid_flag
          , b.lessons_paid
          , b.lesson_paid_type
          , b.cum_balance
          , IFNULL(b.next_payment_date, DATE_FORMAT(m.next_payment_date, '%Y-%m-%d'))                           AS next_payment_date
          , DATEDIFF(IFNULL(b.next_payment_date, DATE_FORMAT(m.next_payment_date, '%Y-%m-%d')) , b.event_day)   AS days_to_next_payment
          , b.next_lesson_date                                                                                  AS next_lesson_date
          , b.days_between_lessons                                                                              AS days_between_lessons
          , IFNULL(sc.in_sc, 0)                                                                                 AS in_schedule
    FROM balances AS b
      LEFT JOIN (SELECT event_day_paid, student_id, next_payment_date FROM paid) AS m ON b.student_id = m.student_id AND b.event_day > event_day_paid
      LEFT JOIN schedule sc ON DATE_FORMAT(b.event_day, '%Y-%m-01') = sc.event_month AND sc.student_id = b.student_id
    WHERE event_day <= IFNULL(b.next_payment_date, DATE_FORMAT(m.next_payment_date, '%Y-%m-%d'))
        OR IFNULL(b.next_payment_date, DATE_FORMAT(m.next_payment_date, '%Y-%m-%d')) IS NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
)


, churn AS (

  SELECT *
        , IF((cum_balance <= 0 AND lesson_flag != 0 AND IFNULL(days_to_next_payment,9) > 8), 1, 0)                                AS is_churn
        , IF((cum_balance > 0 AND days_between_lessons > 30), 1, 0)	                                                              AS is_sleeping
  FROM days
)

, rehab AS (

SELECT *
    , CASE WHEN paid_flag = 1 AND LAG(is_churn, 1) OVER(PARTITION BY student_id ORDER BY event_day ASC) = 1 THEN 1 ELSE 0 END           AS is_churn_rehab
    , CASE WHEN lesson_flag = 1 AND LAG(is_sleeping, 1) OVER(PARTITION BY student_id ORDER BY event_day ASC) = 1 THEN 1 ELSE 0 END      AS is_sleeping_rehab

FROM churn
)


SELECT event_month
      , student_id
      , MAX(is_churn)
      , MAX(is_sleeping)
      , MAX(is_churn_rehab)
      , MAX(is_sleeping_rehab)
      , MAX(in_schedule)
FROM rehab
GROUP BY 1,2
