/*
  stg_employee_contact_information
  --------------------------------
  One row per Coverdash employee (AEs, AMs, ops, ...).

  Notes
    - employee_name is the join key for Business.accountExecutive / accountManager / soldBy
      (text join, exact; names are unique).
*/

with source as (
    select * from {{ source('coverdash_prod', 'EmployeeContactInformation') }}
),

renamed as (
    select
        id                                              as employee_id,
        name                                            as employee_name,
        email,
        "employeeType"                                  as employee_type,
        team,
        "operationsTeam"                                as operations_team,
        coalesce("isActive", false)                     as is_active,
        coalesce("isBelgradeAm", false)                 as is_belgrade_am,
        "startDate"::date                               as start_date,
        "endDate"::date                                 as end_date

    from source
)

select * from renamed
