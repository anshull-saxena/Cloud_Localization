-- ============================================
-- Azure SQL Database Schema for Translation Memory
-- ============================================

-- Create SourceText table to store original text
CREATE TABLE SourceText (
    SourceID INT IDENTITY(1,1) PRIMARY KEY,
    SourceText NVARCHAR(MAX) NOT NULL,
    TargetCultureID NVARCHAR(10) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETDATE(),
    -- Unique constraint to prevent duplicates (limited to 450 chars for indexing)
    CONSTRAINT UQ_SourceText_Culture UNIQUE (SourceText(450), TargetCultureID)
);

-- Create TargetText table to store translations
CREATE TABLE TargetText (
    TargetID INT IDENTITY(1,1) PRIMARY KEY,
    SourceID INT NOT NULL,
    TranslatedText NVARCHAR(MAX) NOT NULL,
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_TargetText_SourceText FOREIGN KEY (SourceID) REFERENCES SourceText(SourceID) ON DELETE CASCADE
);

-- Create indexes for optimized lookups
CREATE INDEX IX_SourceText_Culture ON SourceText(TargetCultureID);
CREATE INDEX IX_TargetText_SourceID ON TargetText(SourceID);

-- Verify tables were created
SELECT 
    TABLE_NAME,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = t.TABLE_NAME) AS ColumnCount
FROM INFORMATION_SCHEMA.TABLES t
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

PRINT '✓ Translation Memory schema created successfully';
