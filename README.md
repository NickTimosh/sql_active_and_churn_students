# Mini-course: From Clever SQL to Maintainable Data Models

Business problem: Identify students who churn, become inactive, and eventually return to an online learning platform.

We'll solve the same problem using three increasingly maintainable approaches.

Case 1 — Clever but Messy SQL

Nested subqueries, repeated calculations, tightly coupled business logic.

Case 2 — Structured SQL with CTEs

Clear transformation steps, descriptive names, easier debugging.

Case 3 — Data Modeling and Medallion Architecture

Reusable facts and dimensions, Bronze → Silver → Gold, modular dbt models.

## Common business rules

For this teaching example, we'll use simplified versions of your original definitions.

| Metric            | Definition                                                                 |
| ----------------- | -------------------------------------------------------------------------- |
| Churn             | Student runs out of lesson credits and makes no new purchase within 8 days |
| Sleeping          | Student has remaining credits but hasn't attended a lesson for 30 days     |
| Churn recovery    | Churned student purchases new lessons                                      |
| Sleeping recovery | Inactive student resumes lessons                                           |
| In schedule       | Student has an active regular schedule or a scheduled single/trial lesson  |

Examples below use Snowflake-style SQL, with `:as_of_date` representing the analysis date. Assume test accounts and invalid lesson events are already filtered. Recovery is evaluated against the student's preceding state.

## Case 1 — The clever SQL query

Hard to maintain

The developer tries to solve everything in one query using nested subqueries, window functions, correlated conditions, and calculations inside calculations.

What's wrong?

- The balance calculation is buried several levels deep.
- Business rules are mixed with event preparation and aggregation.
- Reusing the balance calculation requires copying SQL.
- Adding scheduling or recovery logic makes the query substantially harder to reason about.
- Testing individual transformations is difficult.

Teaching point: A query can be technically sophisticated and still be poorly engineered.

## Case 2 — Clean SQL with CTEs

More maintainable

Now we separate each transformation into a clearly named step. This is inspired by your original implementation, with a few simplifications.

What's improved?

- Each CTE describes one transformation.
- We can debug purchases, lesson consumption, balances, and churn separately.
- The SQL follows the business process from events to metrics.
- New business rules can be introduced without restructuring the entire query.

What's still missing?

The query remains monolithic. If the Finance team needs lesson balances, or the Product team needs student activity history, they must reproduce part of this logic.

Your original implementation already has much of this structure, making it a great intermediate example.

## Case 3 — Data modeling: Bronze → Silver → Gold

Scalable architecture

Instead of writing one large query, we build a data platform in which each transformation has a specific responsibility.

Bronze — Raw data

raw_lesson

raw_passed

raw_calendar

Silver — Cleaned and standardized

stg_payments

stg_lesson_visits

stg_schedules

dim_students

Gold — Facts, dimensions and marts

fct_lesson_transactions

fct_student_activity

fct_student_daily_balance

mart_student_churn

For a production implementation, we'd build daily student-state snapshots, handle the monthly schedule and recovery flags, and keep all historical calculations point-in-time correct.

The key difference is that the churn model no longer needs to understand how raw lesson events are cleaned or how balances are calculated. Those responsibilities belong to upstream models.

## Comparison for your final slide

| Dimension               | Messy SQL         | CTEs                | Data models             |
| ----------------------- | ----------------- | ------------------- | ----------------------- |
| Readability             | Low               | High                | High                    |
| Reusability             | Low               | Limited             | High                    |
| Testing                 | Difficult         | Moderate            | Model-level             |
| Debugging               | Difficult         | Easier              | Isolated                |
| Changing business rules | Risky             | Manageable          | More controlled         |
| Engineering overhead    | Low initially     | Low                 | Higher initially        |
| Best for                | Quick exploration | Standalone analyses | Shared production logic |

## Suggested closing message for the course

> The evolution of a data engineer isn't about writing more complex SQL. It's about reducing the complexity required to understand, reuse, test, and change the logic.

One particularly interesting detail in your historical query is that some CTEs are referenced under different names (`paid` versus `paid_lesson`, `passed` versus `passed_lesson`). There's also a risk of multiplying records when joining multiple payments or lessons on the same day. You could use these as a practical demonstration of how even structured CTE-based SQL can remain fragile without explicit grain definitions and data quality tests.

The strongest teaching example would show how the same student balance can power churn analysis, revenue analytics, student segmentation, and customer support once it's modeled as a reusable data asset.
