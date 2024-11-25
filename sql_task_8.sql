-- Ермолаева Е.А. БПИ 224

-- 1
CREATE OR REPLACE PROCEDURE NEW_JOB(
    p_job_id VARCHAR(10),
    p_job_title VARCHAR(35),
    p_min_salary INTEGER
)
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO jobs (job_id, job_title, min_salary, max_salary)
    VALUES (p_job_id, p_job_title, p_min_salary, p_min_salary * 2);
END;
$$;

CALL NEW_JOB('SY_ANAL', 'System Analyst', 6000);

-- 2
CREATE OR REPLACE PROCEDURE ADD_JOB_HIST(
    p_employee_id INTEGER,
    p_new_job_id VARCHAR(10)
)
    LANGUAGE plpgsql
AS
$$
DECLARE
    v_employee   RECORD;
    v_min_salary NUMERIC(8, 2);
BEGIN
    SELECT * INTO v_employee FROM employees WHERE employee_id = p_employee_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Сотрудник с id = % не существует', p_employee_id;
    END IF;

    SELECT min_salary INTO v_min_salary FROM jobs WHERE job_id = p_new_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Должность с id = % не существует', p_new_job_id;
    END IF;

    INSERT INTO job_history (employee_id, start_date, end_date, job_id, department_id)
    VALUES (p_employee_id,
            v_employee.hire_date,
            CURRENT_DATE,
            v_employee.job_id,
            v_employee.department_id);

    UPDATE employees
    SET hire_date = CURRENT_DATE,
        job_id    = p_new_job_id,
        salary    = v_min_salary + 500
    WHERE employee_id = p_employee_id;
END;
$$;

-- Отключение триггеров
ALTER TABLE employees
    DISABLE TRIGGER ALL;
ALTER TABLE jobs
    DISABLE TRIGGER ALL;
ALTER TABLE job_history
    DISABLE TRIGGER ALL;

CALL ADD_JOB_HIST(106, 'SY_ANAL');

SELECT *
FROM job_history
WHERE employee_id = 106;

SELECT *
FROM employees
WHERE employee_id = 106;

COMMIT;

-- Включение триггеров
ALTER TABLE employees
    ENABLE TRIGGER ALL;
ALTER TABLE jobs
    ENABLE TRIGGER ALL;
ALTER TABLE job_history
    ENABLE TRIGGER ALL;


-- 3

CREATE OR REPLACE PROCEDURE UPD_JOBSAL(
    p_job_id VARCHAR(10),
    new_min_salary INTEGER,
    new_max_salary INTEGER
)
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF new_max_salary < new_min_salary THEN
        RAISE EXCEPTION 'Макс. зарплата (%) меньше минимальной зп (%)', new_max_salary, new_min_salary;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM jobs WHERE job_id = p_job_id) THEN
        RAISE EXCEPTION 'Должность с id % не найдена', p_job_id;
    END IF;

    BEGIN
        UPDATE jobs
        SET min_salary = new_min_salary,
            max_salary = new_max_salary
        WHERE job_id = p_job_id;
    EXCEPTION
        WHEN SQLSTATE '55P03' THEN
            RAISE NOTICE 'Строка с id % заблокирована', p_job_id;
    END;
END;
$$;

CALL UPD_JOBSAL('SY_ANAL', 7000, 140);

ALTER TABLE employees
    DISABLE TRIGGER ALL;
ALTER TABLE jobs
    DISABLE TRIGGER ALL;

CALL UPD_JOBSAL('SY_ANAL', 7000, 14000);

SELECT *
FROM jobs
WHERE job_id = 'SY_ANAL';

ALTER TABLE employees
    ENABLE TRIGGER ALL;
ALTER TABLE jobs
    ENABLE TRIGGER ALL;

COMMIT;

-- 4
CREATE OR REPLACE FUNCTION GET_YEARS_SERVICE(p_employee_id INTEGER)
    RETURNS NUMERIC(5, 2)
    LANGUAGE plpgsql
AS
$$
DECLARE
    v_total_years        NUMERIC(5, 2) := 0;
    v_hire_date          DATE;
    v_today              DATE          := CURRENT_DATE;
    v_employee_exists    BOOLEAN;
    v_job_history_exists BOOLEAN;
BEGIN

    SELECT EXISTS(SELECT 1 FROM employees WHERE employee_id = p_employee_id) INTO v_employee_exists;
    IF NOT v_employee_exists THEN
        RAISE EXCEPTION 'Сотрудник с ID % не существует', p_employee_id;
    END IF;

    SELECT EXISTS(SELECT 1 FROM job_history WHERE employee_id = p_employee_id) INTO v_job_history_exists;

    SELECT hire_date INTO v_hire_date FROM employees WHERE employee_id = p_employee_id;

    v_total_years := (v_today - v_hire_date) / 365.25;

    IF v_job_history_exists THEN
        SELECT SUM((end_date - start_date) / 365.25)
        INTO v_total_years
        FROM job_history
        WHERE employee_id = p_employee_id
        UNION ALL
        SELECT v_total_years;
    END IF;

    RETURN ROUND(v_total_years, 2);
END;
$$;


SELECT GET_YEARS_SERVICE(999); -- выдаст ошибку что нет такого сотрудника

SELECT GET_YEARS_SERVICE(106);

SELECT *
FROM employees
WHERE employee_id = 106;

SELECT *
FROM job_history
WHERE employee_id = 106
ORDER BY start_date;

-- 5
CREATE OR REPLACE FUNCTION GET_JOB_COUNT(p_employee_id INTEGER)
    RETURNS INTEGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    v_job_count INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION 'Сотрудник с id % не существует', p_employee_id;
    END IF;

    SELECT COUNT(DISTINCT job_id)
    INTO v_job_count
    FROM (SELECT job_id
          FROM job_history
          WHERE employee_id = p_employee_id
          UNION
          SELECT job_id
          FROM employees
          WHERE employee_id = p_employee_id) AS all_jobs;

    RETURN v_job_count;
END;
$$;

SELECT GET_JOB_COUNT(176) AS job_count;

SELECT employee_id, job_id
FROM employees
WHERE employee_id = 176;

SELECT employee_id, job_id, start_date
FROM job_history
WHERE employee_id = 176
ORDER BY start_date;

-- 6

CREATE OR REPLACE FUNCTION CHECK_SAL_RANGE()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF EXISTS (SELECT 1
               FROM employees
               WHERE job_id = new.job_id
                 AND (salary < new.min_salary OR salary > new.max_salary)) THEN
        RAISE EXCEPTION 'Зарплата невалидна';
    END IF;

    RETURN NEW;
END;
$$;


CREATE TRIGGER CHECK_SAL_RANGE
    BEFORE UPDATE OF min_salary, max_salary
    ON jobs
    FOR EACH ROW
EXECUTE FUNCTION CHECK_SAL_RANGE();

UPDATE jobs
SET min_salary = 5000,
    max_salary = 7000
WHERE job_id = 'SY_ANAL';

UPDATE jobs
SET min_salary = 7000,
    max_salary = 18000
WHERE job_id = 'SY_ANAL';

UPDATE jobs
SET min_salary = 7000,
    max_salary = 18000
WHERE job_id = 'S';


SELECT job_id, min_salary, max_salary
FROM jobs
WHERE job_id = 'SY_ANAL';

SELECT employee_id, salary
FROM employees
WHERE job_id = 'SY_ANAL';


