IF EXISTS (SELECT name FROM sysobjects WHERE name = 'NGram')
DROP FUNCTION NGram;
GO

-- Lifted from https://www.sqlservercentral.com/articles/nasty-fast-n-grams-part-1-character-level-unigrams
-- Tally table is just a trick to avoid using slow SQL loops
CREATE FUNCTION NGram(@str VARCHAR(255),  @ngram_len INT)
RETURNS TABLE AS
RETURN
	WITH L1(pos) AS (
		SELECT 1 FROM 
		(VALUES 
			(NULL), (NULL), (NULL), (NULL),
			(NULL), (NULL), (NULL), (NULL),
			(NULL), (NULL), (NULL), (NULL),
			(NULL), (NULL), (NULL), (NULL)
		) t(pos)
	), Tally(pos) AS (
			SELECT TOP(len(@str)-(@ngram_len-1))
			ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
			FROM L1 a CROSS JOIN L1 b
	)
	SELECT t.token, COUNT(t.token) cnt 
		FROM (
			SELECT SUBSTRING(@str, pos, @ngram_len) token FROM Tally
		) t
		GROUP BY t.token;
GO