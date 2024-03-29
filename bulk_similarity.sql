IF EXISTS (SELECT name FROM sysobjects WHERE name = 'BulkSimilarity')
DROP FUNCTION BulkSimilarity;
GO


CREATE FUNCTION BulkSimilarity(@str1 VARCHAR(255), @str2 VARCHAR(255), @ngram_len INT = 2)
RETURNS TABLE AS
RETURN
	SELECT
		@str1 String1,
		@str2 String2,
		CONVERT(FLOAT, SUM(t3.v1 * t3.v2)) / (sqrt(SUM(t3.v1 * t3.v1)) * sqrt(SUM(t3.v2 * t3.v2))) Similarity
		FROM (
			SELECT ISNULL(t1.cnt, 0) v1, ISNULL(t2.cnt, 0) v2
			FROM (
				SELECT * FROM dbo.NGram(@str1, @ngram_len)
			) t1
			FULL JOIN
			dbo.NGram(@str2, @ngram_len) t2
			ON t1.Token = t2.Token
		) t3
GO