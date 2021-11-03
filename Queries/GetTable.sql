DECLARE @tableName NVARCHAR(50)

SET @tableName = '$(tableName)'

SELECT [name] -- this column will show up in a powershell object result
FROM sys.tables
WHERE [name] = @tableName;