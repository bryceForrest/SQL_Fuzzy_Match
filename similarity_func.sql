IF EXISTS (SELECT name FROM sysobjects WHERE name = 'Similarity')
DROP FUNCTION Similarity;
GO

CREATE FUNCTION Similarity(@str1 VARCHAR(255), @str2 VARCHAR(255), @ngram_len INT = 2)
RETURNS FLOAT
BEGIN
	DECLARE @similarity FLOAT = (
		SELECT TOP(1) 
			CONVERT(FLOAT, SUM(t3.v1 * t3.v2)) / (sqrt(SUM(t3.v1 * t3.v1)) * sqrt(SUM(t3.v2 * t3.v2)))
			FROM (
				SELECT ISNULL(t1.cnt, 0) v1, ISNULL(t2.cnt, 0) v2
				FROM (
					SELECT * FROM dbo.NGram(@str1, @ngram_len)
				) t1
				FULL JOIN
				dbo.NGram(@str2, @ngram_len) t2
				ON t1.Token = t2.Token
			) t3
	);

	RETURN @similarity
END
GO