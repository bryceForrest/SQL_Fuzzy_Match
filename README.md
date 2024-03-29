# SQL Fuzzy-Matching String Similarity

Well folks, we've done it. As I have little faith we will manage to get any of my external solutions to work in SQL, I've gone ahead and, to the best of my ability, implemented them in SQL. This comes with some downsides, but it should be easy for you guys to maintain in my absence. 

There are two necessary functions, `NGram` and `Similarity`. I trust you guys know better than me how to integrate user-defined SQL functions into your environments so I will skip over that, and will just provide my implementations.

Later I will explain how they work from a conceptual point of view.

## Usage
Suppose we have two strings, and we want some measure of how similar they are.
```SQL
DECLARE @str1 VARCHAR(255) = 'hello world';
DECLARE @str2 VARCHAR(255) = 'jellow sword';

PRINT(dbo.Similarity(@str1, @str2, 2))
```
```
0.476731
```
Which is clearly much more similar than
```SQL
DECLARE @str1 VARCHAR(255) = 'hello world';
DECLARE @str2 VARCHAR(255) = 'its raining spaghetti';

PRINT(dbo.Similarity(@str1, @str2, 2))
```
```
0.06742
```

This function provides a floating-point value between 0 and 1 where words with nothing in common have a score of 0, and exact matches have a value of 1.

For now, ignore that last parameter, the 2 we're passing to the function.

Clearly this is not a very useful example, so let's try something a bit more interesting.

Below we have a real theme name from a performance file. It's not impossible to figure out what they mean by `LEP GOLD RAINBOW BAY MD.01-.10 16L`, but it's not something we can just query SQL for.

```SQL
DECLARE @searchTerm VARCHAR(255) = 'LEP GOLD RAINBOW BAY MD.01-.10 16L'

SELECT Theme_Name
FROM dbo.dimTheme
WHERE Theme_Name = @searchTerm
```
No surprise, this returns nothing. This, however...
```SQL
SELECT TOP(5) Theme_Name, dbo.Similarity(Theme_Name, @searchTerm, 2) Similarity
FROM dbo.dimTheme
ORDER BY Similarity DESC
```
returns this
```
Theme_Name                          Similarity
-----------------------------------------------------
LEPRECHAUNS GOLD - RAINBOW BAY      0.581857365451712
LEPRECHAUNS GOLD - RAINBOW OASIS	0.468979049610542
RAINBOW DRAGON                      0.404519917477945
RAINBOW ROCKS                       0.402015126103685
GOLD GOLD GOLD                      0.382518426118725
```

I would be quite confident in assuming that `LEP GOLD RAINBOW BAY MD.01-.10 16L` is referring to `LEPRECHAUNS GOLD - RAINBOW BAY`.

We are simply comparing our string, `@searchTerm` to every `Theme_Name` in `dbo.dimTheme`, sorting my similarity scores, and returning the top 5. 


We can also do something a bit more substantial, similar to the Bulk Map functionality in the Validation Tool, using something like
```SQL
SELECT t1.Raw_Theme_Name, t2.Theme_Name, t2.Similarity
	FROM (SELECT TOP(100) Raw_Theme_Name FROM dbo.xTheme) t1
	CROSS APPLY(
		SELECT TOP(5) Theme_Name, dbo.Similarity(Theme_Name, t1.Raw_Theme_Name, 2) Similarity
			FROM dbo.dimTheme
			ORDER BY Similarity DESC
	) t2
```

Here we are returning the top 5 matches for the top 100 entries of `dbo.xTheme` (this may or may not be a useful thing to do, it's simply a quick way of getting 100 messy theme names for testing).

**NOTE:** This approach is pretty dang slow, clocking in at about 1 minute in my testing environment. Users of the Validation Tool would weep rivers of pain and sorrow that would flow for 1000 years if the Bulk Map functionality took this long. Later I will suggest an alternative that is less flexible and less readable but much faster (~10 seconds), and I will explain why this SQL implementation will never be as fast as the Validation Tool's Python implementation.

The beauty of this is that you can use it for any string, not just theme names... addresses, account names, cabinets, anything. All it wants are two string and it will compare them.

## How does it work?
While I am sure you guys probably don't care how it works, and are happy to just use a black box, I believe you guys could improve on what I've done and make it more performant... I simply don't have the expertise. Furthermore, while I've tried to make this as portable as possible, I can't guarantee it will work through all the terrible changes Windows might make from now through eternity.

Let's start with a string, `"this thing is a string"`. We are going to start by splitting it into *n-grams*. These are all substrings of size *n* from the string. This was that mysterious 2 we needed for `dbo.Similarity(@str1, @str2, 2)`. We were telling it to use *2-grams* (that is, n-grams with n=2) to calculate the similarity.
Using 2 seems to work pretty well, but you might play with it for different use-cases to see what gives you the best results.

But for now, we'll stick with 2. Our "big-picture" goal here is to generate a dictionary of all 2-grams, and describe our string as a vector (that is, as an ordered sequence of numbers) where each position of the vector has a number representing the number of times that 2-gram occurs in our string (this will make more sense with an example). This is not a perfect numerical representation of our string, since it assumes there couldn't be another string with exactly the same number of occurences of each 2-gram in a different order, but that's pretty unlikely, so it works pretty well. **NOTE:** This is known as "Bag-of-Word embedding" if you need more explanation.

Here's how we generate n-grams in SQL (the user will probably never need to call this function, but `Similarity` will)
```SQL
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
```

The list of 2-grams from `"this thing is a string"` are

```
th
hi
is
s 
 t
th
hi
in
ng
g 
 i
is
s 
 a
a 
 s
st
tr
ri
in
ng
```

But notice we have a few duplicates. Our bag-of-word embedding vector is
```
token   count
-------------
 a	    1
 i	    1
 s	    1
 t	    1
a 	    1
g 	    1
hi	    2
in	    2
is	    2
ng	    2
ri	    1
s 	    2
st	    1
th	    2
tr	    1
```

It will be helpful now to introduce a second string for comparison, `"this ring is for kings"`.

Here is its bag-of-words embedding vector
```
token	count
-------------
 f	    1
 i	    1
 k	    1
 r	    1
fo	    1
g 	    1
gs	    1
hi	    1
in	    2
is	    2
ki	    1
ng	    2
or	    1
r 	    1
ri	    1
s 	    2
th	    1
```

and here are the two of them, `JOIN`ed on shared 2-grams, with zeros filled in for 2-grams that are not shared.
```
token	str1	str2
--------------------
 a	    1	    0
 f	    0	    1
 i  	1	    1
 k	    0	    1
 r	    0   	1
 s	    1	    0
 t	    1   	0
a 	    1   	0
fo	    0   	1
g 	    1   	1
gs	    0   	1
hi	   	2   	1
in  	2   	2
is	    2   	2
ki	    0   	1
ng	   	2   	2
or	    0   	1
r 	    0   	1
ri	    1   	1
s 	    2   	2
st	    1   	0
th	    2   	1
tr	    1   	0
```

But it's still not clear how similar these two vectors are. Luckily, there are a lot of well-defined notions of distance and similarities in vectors.

It's much easier for our human brains to understand pictures, and, while pictures are limited to 3 or less dimensions, the intuition holds for higher dimensions (the number of dimensions a vector is in is determined by the number of elements, so the two string embeddings are in 23 dimensions).

We don't need to get really in-the-weeds here. Just note that, if we think of vectors as arrows, we would expect very similar vectors to be pointing in very similar directions. And if the two arrows are pointing in very similar directions, the angle between the arrows should be very small. If you've never taken a trig class, or you've cleared that information out of your brain for something more useful, just know that the cosine of an angle has the property that, if the angle it 0 (the arrows are pointing in the same direction), the cosine is 1, and if the arrows are perpendicular (pointing in entirely dissimilar directions) the cosine is 1. This is exactly what we want for our similarity function. 

Calculating the cosine of the angle between two vectors is pretty easy. It's just the *dot product* of the two vectors, divided by the product of the *magnitude* of both vectors.

![alt text](vectors.png "Cosine Similarity")


In the case of our two string vector embeddings, the dot product is simply the sum of the product of each row, so
```
1*0 + 0*1 + 1*1 + 0*1 + ... + 2*1 + 1*0 = 23
```

The magnitude of each vector is the square root of the sum of each element squared (think Pythagorean theorem). So,
```
sqrt(1^2 + 0^2 + 1^2 + ... + 2^2 + 1^2) = 5.74456
```
and
```
sqrt(0^2 + 1^2 + 1^2 + ... + 1^2 + 0^2) = 5.38516
```

So the cosine similarity of the two strings is simply
```
23 / (5.74456 * 5.38516) = 0.743485
```

Which agrees with our fancy new SQL function
```SQL
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
```
```SQL
PRINT(dbo.Similarity('this thing is a string', 'this ring is for kings', 2))
```

```
0.743484
```

A couple of clarifying points:
1. I said that we wanted a dictionary of all 2-grams. This is clearly not that. However, when comparing the vector embeddings of two strings, any 2-grams that do not appear in either string will have a count of 0 in both, and therefore will not contribute to the calculation of the cosine similarity.

2. I also said that the embeddings were ordered. The `JOIN` takes care of this for us though, since 2-grams that are shared between both strings will be in the same row position, and ones that are not shared will be multiplied by 0.

## A few last words
First, I mentioned a faster way to imitate the Bulk Fill functionality in the Validation Tool, so here that is.

First, a slight alteration of `Similarity` into an inline table-valued function, since calling those has no overhead:

```SQL
CREATE FUNCTION BulkSimilarity(@str1 VARCHAR(255), @str2 VARCHAR(255), @ngram_len INT = 2)
RETURNS TABLE AS
RETURN
	SELECT
		@str1 String1,
		@str2 String2,
		CONVERT(FLOAT, SUM(t3.v1 * t3.v2)) / (SQRT(SUM(t3.v1 * t3.v1)) * SQRT(SUM(t3.v2 * t3.v2))) Similarity
		FROM (
			SELECT ISNULL(t1.cnt, 0) v1, ISNULL(t2.cnt, 0) v2
			FROM (
				SELECT * FROM dbo.NGram(@str1, @ngram_len)
			) t1
			FULL JOIN
			dbo.NGram(@str2, @ngram_len) t2
			ON t1.Token = t2.Token
		) t3
```

```SQL
WITH CartesianProduct AS (
	SELECT t1.Raw_Theme_Name, t2.Theme_Name
	FROM (SELECT TOP(100) Raw_Theme_Name FROM dbo.xTheme) t1, dbo.dimTheme t2
)
SELECT Raw_Theme_Name, Theme_Name, Similarity FROM (
	SELECT CartesianProduct.*, sim.Similarity,
	ROW_NUMBER() OVER (PARTITION BY Raw_Theme_Name ORDER BY sim.Similarity DESC) r
	FROM CartesianProduct
	OUTER APPLY
	dbo.BulkSimilarity(Raw_Theme_Name, Theme_Name, 2) sim
) results
WHERE r <= 5
```

So this will generate the Cartesian product of `dimTheme` and `xTheme`, so we can generate the similarity between every pair (be careful with this, you might make something huge and unwieldy, but 100 by 2954 is not bad). It then essentially `UNION`s the top 5 matches of each string by an `OUTER APPLY` of the results from the TVF `BulkSimilarity`. It can handle this in ~10 seconds. It's a bit more difficult to read and harder to pack into a function, so do with it what you will.

Second, if you're already playing around with it, or you are very astute, you may have two questions.

1. Why are my scores not as good as the scores I get in the Validation Tool?

2. Why is this so much slower than the Python implementation? Shouldn't it be faster since it's not calling an external language?

Or maybe you haven't asked these questions at all. Let's address them though.

1. The Validation Tool implementation of Fuzzy Match has some extra functionality built in. It looks at old mappings of `Raw_Theme_Name`s to `Theme_Name`s, generates the bag-of-word embeddings for each column, and uses some linear algebra wizardry to calculate weights for each n-gram. This is the magic behind being able to look up something like `QHJPTB7s` and getting back `QUICK HIT JACKPOT TRIPLE BLAZING 7S`... it's simply because we've mapped it to that in the past. Think of it as squishing and stretching the space around the vectors so that two arrows that previously weren't pointing in the same direction now are. This is not practical to implement in SQL, at least not for me. It requires either the patience of a saint or a linear algebra package to implement. I wouldn't hold your breath for either.

2. The reason the Python implementation is so fast is because it "fits" to the dataset we are searching on all at once, and then never again. That is, it generates all the bag-of-word embeddings for everything in `dimTheme` and stores them in RAM for fast accessibility. This means it takes a little longer to start the program, but searches are near-instant. The SQL implementation generates the bag-of-word embeddings for both strings ***every single time***. This is far from optimal. So, for example, when matching 100 messy them names to `dimTheme`, it generates the same embedding for every theme name in `dimTheme` 100 times. It would be much better to store them somewhere, but this was not something I could wrap my brain around. This is, however, something I think you guys could figure out. You could probably write a stored procedure that runs every night and creates a table with n-grams as rows and theme names as columns (or vice versa?) and search against that. Maybe. I don't know.

### Good luck!