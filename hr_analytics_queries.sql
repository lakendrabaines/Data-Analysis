
-- 1. Employee Count by Department
SELECT department, COUNT(*) AS total_employees
FROM Employees
GROUP BY department;

-- 2. Average Salary by Department
SELECT department, ROUND(AVG(salary), 2) AS avg_salary
FROM Employees
GROUP BY department;

-- 3. Gender Distribution
SELECT gender, COUNT(*) AS count
FROM Employees
GROUP BY gender;

-- 4. Employees with Performance Rating >= 4
SELECT first_name || ' ' || last_name AS employee_name, department, performance_rating
FROM Employees
WHERE performance_rating >= 4;

-- 5. Attendance Summary
SELECT e.first_name || ' ' || e.last_name AS employee_name, a.status, COUNT(*) AS days
FROM Attendance a
JOIN Employees e ON a.employee_id = e.employee_id
GROUP BY a.employee_id, a.status
ORDER BY employee_name;

-- 6. Average Training Score by Department
SELECT e.department, ROUND(AVG(t.score), 2) AS avg_training_score
FROM Training t
JOIN Employees e ON t.employee_id = e.employee_id
GROUP BY e.department;

-- 7. Exit Summary by Reason
SELECT reason, COUNT(*) AS total_exits
FROM Exits
GROUP BY reason;

-- 8. Employees Who Left the Company
SELECT e.first_name || ' ' || e.last_name AS employee_name, e.department, ex.exit_date, ex.reason
FROM Exits ex
JOIN Employees e ON ex.employee_id = e.employee_id;
