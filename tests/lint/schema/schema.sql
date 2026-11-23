/* Lane FR-LINT fixture: the tables link-orm matches the ORM classes of uBounds.pas against.
   Lengths here are NOT read by the schema rules -- those come from the field repository (repo.txt). */
CREATE TABLE MSCLIST (
  DIMNAME VARCHAR(35),
  DIMABBR VARCHAR(10)
);

CREATE TABLE ORDERS (
  ID INTEGER NOT NULL,
  NOTE VARCHAR(20)
);
