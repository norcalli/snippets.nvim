# What is a snippet?

A snippet is a complicated structure representing potentially deferred
evaluated sections of strings representing the final string to be inserted into
code and a variable dictionary representing user input.

This can be seen in something like

```
The ${2:latter $1} is a version of $1
```

The 


There is an evaluation order:
- Evaluate something at the time the snippet is expanded.
	- This something could potentially have a "name" so that it could be used
  in multiple places to be inserted. In this system, we use a negative variable to indicate this.
- Evaluate a transformation on the input that the user inputted up to that point.
	- This could be after any one of the variables



```
{
	"verbatim"; { variable_name = 1; evaluation_order = -1; };
  { variable_name = 2; evaluation_order = 1; };
  { variable_name = ANONYMOUS; evaluation_order = -1; };
  { evaluation_order = 0; };
}
```

The value of every non-anonymous variable should be available after evaluation.

Every variable can have a default value. The default value can be a string OR
a function, which shall be passed the variable dictionary at the time of evaluation.

Every variable can have a transformation attached to it to modify its value
after the fact which is LOCAL TO THE POSITION IN WHICH IT IS EXPANDED. If a
variable is used in multiple places, the transformation one position doesn't
affect all positions.
