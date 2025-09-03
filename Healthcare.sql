/* Reference tables */
CREATE TABLE DiagnosisCode (
DxCode TEXT PRIMARY KEY, -- e.g., 'I10'
DxDescription TEXT NOT NULL
);


CREATE TABLE ProcedureCode (
ProcCode TEXT PRIMARY KEY, -- e.g., '99213'
ProcDescription TEXT NOT NULL
);


CREATE TABLE Medication (
MedicationID INTEGER PRIMARY KEY AUTOINCREMENT,
RxName TEXT NOT NULL,
Form TEXT,
Strength TEXT
);


CREATE TABLE Payer (
PayerID INTEGER PRIMARY KEY AUTOINCREMENT,
PayerName TEXT NOT NULL,
PayerType TEXT -- Commercial, Medicare, Medicaid, Self‑Pay
);


CREATE TABLE InsurancePlan (
PlanID INTEGER PRIMARY KEY AUTOINCREMENT,
PayerID INTEGER NOT NULL REFERENCES Payer(PayerID),
PlanName TEXT NOT NULL
);


/* Core master tables */
CREATE TABLE Patient (
PatientID INTEGER PRIMARY KEY AUTOINCREMENT,
MRN TEXT NOT NULL UNIQUE,
FirstName TEXT NOT NULL,
LastName TEXT NOT NULL,
DOB TEXT NOT NULL, -- 'YYYY-MM-DD'
Sex TEXT NOT NULL CHECK (Sex IN ('F','M','O')),
Phone TEXT
);


CREATE TABLE Provider (
ProviderID INTEGER PRIMARY KEY AUTOINCREMENT,
NPI TEXT UNIQUE,
FirstName TEXT NOT NULL,
LastName TEXT NOT NULL,
Specialty TEXT
);


CREATE TABLE Facility (
FacilityID INTEGER PRIMARY KEY AUTOINCREMENT,
FacilityName TEXT NOT NULL,
City TEXT,
State TEXT
);


/* Coverage over time */
CREATE TABLE PatientCoverage (
);