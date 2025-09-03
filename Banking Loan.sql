-- Enable FKs
PRAGMA foreign_keys = ON;

-- ======================
-- LOOKUPS
-- ======================
CREATE TABLE AccountType (
  AccountTypeCode TEXT PRIMARY KEY,    -- 'CHK','SAV'
  TypeName        TEXT NOT NULL,
  DefaultOverdraftAllowed INTEGER NOT NULL DEFAULT 0,   -- 0/1
  DefaultOverdraftLimit   NUMERIC NOT NULL DEFAULT 0
);

CREATE TABLE LoanType (
  LoanTypeCode TEXT PRIMARY KEY,       -- 'AUTO','MORTGAGE','PERSONAL'
  TypeName     TEXT NOT NULL,
  AmortizationMethod TEXT NOT NULL CHECK (AmortizationMethod IN ('Amortized','InterestOnly')),
  CollateralRequired INTEGER NOT NULL DEFAULT 0,
  MaxTermMonths INTEGER
);

-- ======================
-- CORE TABLES
-- ======================
CREATE TABLE Branch (
  BranchID   INTEGER PRIMARY KEY AUTOINCREMENT,
  BranchName TEXT NOT NULL,
  City       TEXT,
  State      TEXT
);

CREATE TABLE Customer (
  CustomerID   INTEGER PRIMARY KEY AUTOINCREMENT,
  FirstName    TEXT NOT NULL,
  LastName     TEXT NOT NULL,
  Email        TEXT UNIQUE,
  Phone        TEXT,
  DOB          TEXT,                           -- 'YYYY-MM-DD'
  IncomeAnnual NUMERIC CHECK (IncomeAnnual IS NULL OR IncomeAnnual >= 0)
);

-- Deposit accounts
CREATE TABLE Account (
  AccountID        INTEGER PRIMARY KEY AUTOINCREMENT,
  CustomerID       INTEGER NOT NULL REFERENCES Customer(CustomerID),
  BranchID         INTEGER NOT NULL REFERENCES Branch(BranchID),
  AccountTypeCode  TEXT NOT NULL REFERENCES AccountType(AccountTypeCode),
  OpenDate         TEXT NOT NULL,              -- 'YYYY-MM-DD'
  CloseDate        TEXT,
  OverdraftAllowed INTEGER NOT NULL DEFAULT 0,
  OverdraftLimit   NUMERIC NOT NULL DEFAULT 0,
  Balance          NUMERIC NOT NULL DEFAULT 0,
  CHECK (OverdraftLimit >= 0)
);

CREATE TABLE AccountTransaction (
  TxnID        INTEGER PRIMARY KEY AUTOINCREMENT,
  AccountID    INTEGER NOT NULL REFERENCES Account(AccountID),
  TxnType      TEXT NOT NULL CHECK (TxnType IN ('DEPOSIT','WITHDRAWAL','TRANSFER_IN','TRANSFER_OUT','FEE','INTEREST')),
  Amount       NUMERIC NOT NULL CHECK (Amount > 0),
  TxnTimestamp TEXT NOT NULL,                  -- 'YYYY-MM-DDTHH:MM:SS'
  Description  TEXT
);

-- Loans
CREATE TABLE Loan (
  LoanID            INTEGER PRIMARY KEY AUTOINCREMENT,
  CustomerID        INTEGER NOT NULL REFERENCES Customer(CustomerID),
  BranchID          INTEGER NOT NULL REFERENCES Branch(BranchID),
  LoanTypeCode      TEXT NOT NULL REFERENCES LoanType(LoanTypeCode),
  PrincipalAmount   NUMERIC NOT NULL CHECK (PrincipalAmount > 0),
  APR               NUMERIC NOT NULL CHECK (APR > 0), -- e.g., 6.5 => 6.5%
  TermMonths        INTEGER NOT NULL CHECK (TermMonths > 0),
  StartDate         TEXT NOT NULL,                    -- 'YYYY-MM-DD'
  PaymentDueDay     INTEGER NOT NULL CHECK (PaymentDueDay BETWEEN 1 AND 31),
  CurrentPrincipal  NUMERIC NOT NULL,                 -- initialize = PrincipalAmount
  AccruedInterest   NUMERIC NOT NULL DEFAULT 0,
  Status            TEXT NOT NULL DEFAULT 'Active' CHECK (Status IN ('Active','Closed','ChargedOff')),
  OriginationFee    NUMERIC NOT NULL DEFAULT 0
);

CREATE TABLE Collateral (
  CollateralID   INTEGER PRIMARY KEY AUTOINCREMENT,
  LoanID         INTEGER NOT NULL REFERENCES Loan(LoanID) ON DELETE CASCADE,
  CollateralType TEXT NOT NULL,  -- Vehicle, Property, Other
  Description    TEXT,
  AppraisedValue NUMERIC CHECK (AppraisedValue IS NULL OR AppraisedValue >= 0)
);

-- Amortization schedule
CREATE TABLE AmortizationSchedule (
  ScheduleID     INTEGER PRIMARY KEY AUTOINCREMENT,
  LoanID         INTEGER NOT NULL REFERENCES Loan(LoanID) ON DELETE CASCADE,
  PaymentNumber  INTEGER NOT NULL,
  DueDate        TEXT NOT NULL,         -- 'YYYY-MM-DD'
  DueAmount      NUMERIC NOT NULL,
  PrincipalDue   NUMERIC NOT NULL,
  InterestDue    NUMERIC NOT NULL,
  PrincipalPaid  NUMERIC NOT NULL DEFAULT 0,
  InterestPaid   NUMERIC NOT NULL DEFAULT 0,
  UNIQUE (LoanID, PaymentNumber)
);

-- Loan payments (raw ledger)
CREATE TABLE Payment (
  PaymentID   INTEGER PRIMARY KEY AUTOINCREMENT,
  LoanID      INTEGER NOT NULL REFERENCES Loan(LoanID),
  PaymentDate TEXT NOT NULL,    -- 'YYYY-MM-DD'
  Amount      NUMERIC NOT NULL CHECK (Amount > 0),
  Method      TEXT CHECK (Method IN ('CASH','TRANSFER','ACH','CARD','CHECK')),
  Note        TEXT
);

-- ======================
-- TRIGGERS
-- ======================

-- Apply account transactions & enforce overdraft policy
CREATE TRIGGER trg_AccountTransaction_Apply
AFTER INSERT ON AccountTransaction
BEGIN
  -- Compute delta: deposits add, withdrawals/fees subtract
  UPDATE Account
  SET Balance = Balance + (
    SELECT SUM(
      CASE
        WHEN TxnType IN ('DEPOSIT','TRANSFER_IN','INTEREST') THEN Amount
        ELSE -Amount
      END
    )
    FROM AccountTransaction
    WHERE RowID IN (SELECT RowID FROM inserted)
      AND AccountTransaction.AccountID = Account.AccountID
  )
  WHERE AccountID IN (SELECT AccountID FROM inserted);

  -- Reject if overdraft rules violated (simulate by raising error using CHECK trick)
  -- SQLite lacks RAISE in AFTER UPDATE directly here, so we ensure no bad row persists:
  -- Create a constraint table to force failure if any violation occurs.
END;

-- Hard-enforce overdraft with BEFORE trigger (SQLite supports RAISE in BEFORE)
DROP TRIGGER IF EXISTS trg_AccountTransaction_Before;
CREATE TRIGGER trg_AccountTransaction_Before
BEFORE INSERT ON AccountTransaction
BEGIN
  -- projected new balance for target account considering this single row
  SELECT
    CASE
      WHEN (
        SELECT
          CASE
            WHEN NEW.TxnType IN ('DEPOSIT','TRANSFER_IN','INTEREST')
              THEN (SELECT Balance FROM Account WHERE AccountID = NEW.AccountID) + NEW.Amount
            ELSE (SELECT Balance FROM Account WHERE AccountID = NEW.AccountID) - NEW.Amount
          END
      ) < 0
      AND (SELECT OverdraftAllowed FROM Account WHERE AccountID = NEW.AccountID) = 0
      THEN RAISE(ABORT, 'Overdraft not allowed')
    END;

  SELECT
    CASE
      WHEN (
        SELECT
          CASE
            WHEN NEW.TxnType IN ('DEPOSIT','TRANSFER_IN','INTEREST')
              THEN (SELECT Balance FROM Account WHERE AccountID = NEW.AccountID) + NEW.Amount
            ELSE (SELECT Balance FROM Account WHERE AccountID = NEW.AccountID) - NEW.Amount
          END
      ) < -(SELECT OverdraftLimit FROM Account WHERE AccountID = NEW.AccountID)
      AND (SELECT OverdraftAllowed FROM Account WHERE AccountID = NEW.AccountID) = 1
      THEN RAISE(ABORT, 'Overdraft limit exceeded')
    END;
END;

-- ======================
-- VIEWS (analytics)
-- ======================
CREATE VIEW v_LoanPortfolioSummary AS
SELECT
  LoanTypeCode,
  Status,
  COUNT(*) AS LoanCount,
  SUM(CurrentPrincipal) AS OutstandingPrincipal,
  AVG(APR) AS AvgAPR
FROM Loan
GROUP BY LoanTypeCode, Status;

-- Next unpaid row per loan
CREATE VIEW v_DelinquencyAging AS
WITH next_unpaid AS (
  SELECT
    LoanID,
    MIN(DueDate) AS NextUnpaidDue
  FROM AmortizationSchedule
  WHERE (PrincipalPaid + InterestPaid) < DueAmount
  GROUP BY LoanID
)
SELECT
  l.LoanID,
  l.CustomerID,
  l.LoanTypeCode,
  l.Status,
  n.NextUnpaidDue,
  CASE
    WHEN n.NextUnpaidDue IS NULL THEN 0
    ELSE CAST((julianday(date('now')) - julianday(n.NextUnpaidDue)) AS INT)
  END AS DaysPastDue,
  CASE
    WHEN n.NextUnpaidDue IS NULL OR date('now') <= n.NextUnpaidDue THEN '0'
    WHEN (julianday(date('now')) - julianday(n.NextUnpaidDue)) BETWEEN 1 AND 30 THEN '1-30'
    WHEN (julianday(date('now')) - julianday(n.NextUnpaidDue
