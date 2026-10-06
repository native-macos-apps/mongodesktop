import Foundation

enum QueryCompletionCatalog {

    // MARK: - Query Operators

    static let queryOperators: [QueryCompletionItem] = [
        // Comparison
        QueryCompletionItem(
            label: "$eq",
            kind: .queryOperator,
            detail: "Matches values that are equal to a specified value",
            documentation: "Syntax: { <field>: { $eq: <value> } }\n\nSpecifies equality condition. Equivalent to { field: value } for most queries."
        ),
        QueryCompletionItem(
            label: "$ne",
            kind: .queryOperator,
            detail: "Matches all values that are not equal to a specified value",
            documentation: "Syntax: { <field>: { $ne: <value> } }\n\nSelects the documents where the value of the field is not equal to the specified value."
        ),
        QueryCompletionItem(
            label: "$gt",
            kind: .queryOperator,
            detail: "Matches values that are greater than a specified value",
            documentation: "Syntax: { <field>: { $gt: <value> } }\n\nSelects documents where the value is strictly greater than the given value."
        ),
        QueryCompletionItem(
            label: "$gte",
            kind: .queryOperator,
            detail: "Matches values that are greater than or equal to a specified value",
            documentation: "Syntax: { <field>: { $gte: <value> } }\n\nSelects documents where the value is greater than or equal to the given value."
        ),
        QueryCompletionItem(
            label: "$lt",
            kind: .queryOperator,
            detail: "Matches values that are less than a specified value",
            documentation: "Syntax: { <field>: { $lt: <value> } }\n\nSelects documents where the value is strictly less than the given value."
        ),
        QueryCompletionItem(
            label: "$lte",
            kind: .queryOperator,
            detail: "Matches values that are less than or equal to a specified value",
            documentation: "Syntax: { <field>: { $lte: <value> } }\n\nSelects documents where the value is less than or equal to the given value."
        ),
        QueryCompletionItem(
            label: "$in",
            kind: .queryOperator,
            detail: "Matches any of the values specified in an array",
            documentation: "Syntax: { <field>: { $in: [<value1>, <value2>, ...] } }\n\nSelects documents where the value matches any member of the specified array.",
            insertText: "$in: []",
            cursorOffset: 5
        ),
        QueryCompletionItem(
            label: "$nin",
            kind: .queryOperator,
            detail: "Matches none of the values specified in an array",
            documentation: "Syntax: { <field>: { $nin: [<value1>, <value2>, ...] } }\n\nSelects documents where the value does not equal any value in the specified array.",
            insertText: "$nin: []",
            cursorOffset: 6
        ),

        // Logical
        QueryCompletionItem(
            label: "$and",
            kind: .queryOperator,
            detail: "Joins query clauses with a logical AND",
            documentation: "Syntax: { $and: [ { <expression1> }, { <expression2> } ] }\n\nPerforms a logical AND operation on an array of one or more expressions.",
            insertText: "$and: [\n  {\n    \n  }\n]",
            cursorOffset: 15
        ),
        QueryCompletionItem(
            label: "$or",
            kind: .queryOperator,
            detail: "Joins query clauses with a logical OR",
            documentation: "Syntax: { $or: [ { <expression1> }, { <expression2> } ] }\n\nPerforms a logical OR operation on an array of two or more expressions.",
            insertText: "$or: [\n  {\n    \n  }\n]",
            cursorOffset: 14
        ),
        QueryCompletionItem(
            label: "$not",
            kind: .queryOperator,
            detail: "Inverts the effect of a query expression",
            documentation: "Syntax: { <field>: { $not: { <operator-expression> } } }\n\nPerforms a logical NOT on the specified expression."
        ),
        QueryCompletionItem(
            label: "$nor",
            kind: .queryOperator,
            detail: "Joins query clauses with a logical NOR",
            documentation: "Syntax: { $nor: [ { <expression1> }, { <expression2> } ] }\n\nSelects documents that fail all the query clauses in the array.",
            insertText: "$nor: [\n  {\n    \n  }\n]",
            cursorOffset: 15
        ),

        // Element
        QueryCompletionItem(
            label: "$exists",
            kind: .queryOperator,
            detail: "Matches documents that have the specified field",
            documentation: "Syntax: { <field>: { $exists: <boolean> } }\n\nMatches documents that contain or do not contain the specified field.",
            insertText: "$exists: true",
            cursorOffset: 13
        ),
        QueryCompletionItem(
            label: "$type",
            kind: .queryOperator,
            detail: "Selects documents if a field is of the specified type",
            documentation: "Syntax: { <field>: { $type: <BSON type> } }\n\nE.g. \"string\", \"int\", \"double\", \"bool\", \"date\", \"objectId\", \"array\", \"object\"."
        ),

        // Evaluation
        QueryCompletionItem(
            label: "$regex",
            kind: .queryOperator,
            detail: "Selects documents where values match a specified regular expression",
            documentation: "Syntax: { <field>: { $regex: /pattern/, $options: 'i' } }\n\nProvides regular expression capabilities for pattern matching strings.",
            insertText: "$regex: \"\", $options: \"i\"",
            cursorOffset: 9
        ),
        QueryCompletionItem(
            label: "$expr",
            kind: .queryOperator,
            detail: "Allows the use of aggregation expressions within the query language",
            documentation: "Syntax: { $expr: { <expression> } }\n\nCompares fields within the same document or uses aggregation operators in find queries."
        ),
        QueryCompletionItem(
            label: "$mod",
            kind: .queryOperator,
            detail: "Performs a modulo operation on the value of a field",
            documentation: "Syntax: { <field>: { $mod: [ <divisor>, <remainder> ] } }"
        ),
        QueryCompletionItem(
            label: "$text",
            kind: .queryOperator,
            detail: "Performs text search on a text index",
            documentation: "Syntax: { $text: { $search: <string> } }\n\nPerforms text search on fields with a text index."
        ),

        // Array
        QueryCompletionItem(
            label: "$all",
            kind: .queryOperator,
            detail: "Matches arrays that contain all elements specified in the query",
            documentation: "Syntax: { <field>: { $all: [ <value1>, <value2>, ... ] } }"
        ),
        QueryCompletionItem(
            label: "$elemMatch",
            kind: .queryOperator,
            detail: "Selects documents if element in the array field matches all the specified conditions",
            documentation: "Syntax: { <field>: { $elemMatch: { <query1>, <query2>, ... } } }\n\nMatches array elements that satisfy all query criteria.",
            insertText: "$elemMatch: {  }",
            cursorOffset: 14
        ),
        QueryCompletionItem(
            label: "$size",
            kind: .queryOperator,
            detail: "Selects documents if the array field is a specified size",
            documentation: "Syntax: { <field>: { $size: <number> } }"
        ),

        // Update operators
        QueryCompletionItem(
            label: "$set",
            kind: .queryOperator,
            detail: "Sets the value of a field in a document",
            documentation: "Syntax: { $set: { <field1>: <value1>, ... } }\n\nReplaces the value of a field with the specified value.",
            insertText: "$set: {  }",
            cursorOffset: 8
        ),
        QueryCompletionItem(
            label: "$unset",
            kind: .queryOperator,
            detail: "Deletes a particular field from a document",
            documentation: "Syntax: { $unset: { <field1>: \"\", ... } }"
        ),
        QueryCompletionItem(
            label: "$inc",
            kind: .queryOperator,
            detail: "Increments the value of the field by the specified amount",
            documentation: "Syntax: { $inc: { <field1>: <amount1>, ... } }"
        ),
        QueryCompletionItem(
            label: "$push",
            kind: .queryOperator,
            detail: "Appends a specified value to an array",
            documentation: "Syntax: { $push: { <field1>: <value1>, ... } }"
        ),
        QueryCompletionItem(
            label: "$pull",
            kind: .queryOperator,
            detail: "Removes from an existing array all instances of a value that match a condition",
            documentation: "Syntax: { $pull: { <field1>: <value|condition>, ... } }"
        ),
        QueryCompletionItem(
            label: "$addToSet",
            kind: .queryOperator,
            detail: "Adds elements to an array only if they do not already exist in the set",
            documentation: "Syntax: { $addToSet: { <field1>: <value1>, ... } }"
        )
    ]

    // MARK: - Aggregation Stages

    static let aggregateStages: [QueryCompletionItem] = [
        QueryCompletionItem(
            label: "$match",
            kind: .aggregateStage,
            detail: "Filters documents to allow only matching documents into the next pipeline stage",
            documentation: "Syntax: { $match: { <query> } }\n\nFilters the documents to pass only the documents that match the specified condition(s).",
            insertText: "$match: {\n  \n}",
            cursorOffset: 11
        ),
        QueryCompletionItem(
            label: "$project",
            kind: .aggregateStage,
            detail: "Passes along the documents with requested fields or computed fields",
            documentation: "Syntax: { $project: { <specification> } }\n\nReshapes each document in the stream, such as by adding new fields or removing existing fields.",
            insertText: "$project: {\n  \n}",
            cursorOffset: 13
        ),
        QueryCompletionItem(
            label: "$group",
            kind: .aggregateStage,
            detail: "Groups input documents by the specified _id expression and calculates accumulators",
            documentation: "Syntax: { $group: { _id: <expression>, <field1>: { <accumulator1>: <expr1> } } }\n\nGroups documents by a specified identifier.",
            insertText: "$group: {\n  _id: \"$\",\n  count: { $sum: 1 }\n}",
            cursorOffset: 17
        ),
        QueryCompletionItem(
            label: "$sort",
            kind: .aggregateStage,
            detail: "Reorders documents by the specified sort key(s)",
            documentation: "Syntax: { $sort: { <field1>: 1 | -1, ... } }\n\n1 = ascending, -1 = descending.",
            insertText: "$sort: { : 1 }",
            cursorOffset: 9
        ),
        QueryCompletionItem(
            label: "$limit",
            kind: .aggregateStage,
            detail: "Limits the number of documents passed to the next stage",
            documentation: "Syntax: { $limit: <positive integer> }",
            insertText: "$limit: 50",
            cursorOffset: 10
        ),
        QueryCompletionItem(
            label: "$skip",
            kind: .aggregateStage,
            detail: "Skips over the specified number of documents",
            documentation: "Syntax: { $skip: <positive integer> }",
            insertText: "$skip: 0",
            cursorOffset: 8
        ),
        QueryCompletionItem(
            label: "$unwind",
            kind: .aggregateStage,
            detail: "Deconstructs an array field from the input documents to output a document for each element",
            documentation: "Syntax: { $unwind: \"$<field>\" } or { $unwind: { path: \"$<field>\", preserveNullAndEmptyArrays: true } }",
            insertText: "$unwind: \"$\"",
            cursorOffset: 10
        ),
        QueryCompletionItem(
            label: "$lookup",
            kind: .aggregateStage,
            detail: "Performs a left outer join to an unsharded collection in the same database",
            documentation: "Syntax:\n{\n  $lookup: {\n    from: <collection>,\n    localField: <field>,\n    foreignField: <field>,\n    as: <output array>\n  }\n}",
            insertText: "$lookup: {\n  from: \"\",\n  localField: \"\",\n  foreignField: \"_id\",\n  as: \"joined\"\n}",
            cursorOffset: 20
        ),
        QueryCompletionItem(
            label: "$addFields",
            kind: .aggregateStage,
            detail: "Adds new fields to documents",
            documentation: "Syntax: { $addFields: { <newField>: <expression>, ... } }\n\nSimilar to $project, but maintains all existing fields without having to explicitly specify them.",
            insertText: "$addFields: {\n  \n}",
            cursorOffset: 15
        ),
        QueryCompletionItem(
            label: "$set",
            kind: .aggregateStage,
            detail: "Alias for $addFields. Adds new fields to documents",
            documentation: "Syntax: { $set: { <field1>: <expression1>, ... } }",
            insertText: "$set: {\n  \n}",
            cursorOffset: 9
        ),
        QueryCompletionItem(
            label: "$unset",
            kind: .aggregateStage,
            detail: "Removes/excludes fields from documents",
            documentation: "Syntax: { $unset: [ \"<field1>\", ... ] } or { $unset: \"<field>\" }",
            insertText: "$unset: [ \"\" ]",
            cursorOffset: 11
        ),
        QueryCompletionItem(
            label: "$count",
            kind: .aggregateStage,
            detail: "Passes a document to the next stage containing a count of incoming documents",
            documentation: "Syntax: { $count: \"<outputField>\" }",
            insertText: "$count: \"total\"",
            cursorOffset: 15
        ),
        QueryCompletionItem(
            label: "$facet",
            kind: .aggregateStage,
            detail: "Processes multiple aggregation pipelines within a single stage on the same set of input documents",
            documentation: "Syntax: { $facet: { <outputField1>: [ <stage1>, ... ], ... } }"
        ),
        QueryCompletionItem(
            label: "$replaceRoot",
            kind: .aggregateStage,
            detail: "Replaces the input document with the specified document",
            documentation: "Syntax: { $replaceRoot: { newRoot: <replacementDocument> } }"
        ),
        QueryCompletionItem(
            label: "$sample",
            kind: .aggregateStage,
            detail: "Randomly selects the specified number of documents from its input",
            documentation: "Syntax: { $sample: { size: <positive integer> } }",
            insertText: "$sample: { size: 10 }",
            cursorOffset: 19
        ),
        QueryCompletionItem(
            label: "$unionWith",
            kind: .aggregateStage,
            detail: "Performs a union of two collections",
            documentation: "Syntax: { $unionWith: { coll: \"<collection>\", pipeline: [ <stage1>, ... ] } }",
            insertText: "$unionWith: {\n  coll: \"\"\n}",
            cursorOffset: 24
        ),
        QueryCompletionItem(
            label: "$out",
            kind: .aggregateStage,
            detail: "Writes the resulting documents of the aggregation pipeline to a specified collection",
            documentation: "Syntax: { $out: \"<collection>\" }"
        ),
        QueryCompletionItem(
            label: "$merge",
            kind: .aggregateStage,
            detail: "Writes the resulting documents to an existing or new collection",
            documentation: "Syntax: { $merge: { into: \"<collection>\", on: \"_id\", whenMatched: \"replace\", whenNotMatched: \"insert\" } }"
        )
    ]

    // MARK: - BSON Helper Types

    static let bsonHelpers: [QueryCompletionItem] = [
        QueryCompletionItem(
            label: "ObjectId",
            kind: .bsonHelper,
            detail: "Constructs a 12-byte BSON ObjectId",
            documentation: "Syntax: ObjectId(\"hexString\") or ObjectId()\n\nCreates a unique MongoDB document identifier.",
            insertText: "ObjectId(\"\")",
            cursorOffset: 10,
            isKey: false
        ),
        QueryCompletionItem(
            label: "ISODate",
            kind: .bsonHelper,
            detail: "Constructs an ISO-8601 Date object",
            documentation: "Syntax: ISODate(\"YYYY-MM-DDTHH:mm:ss.sssZ\") or ISODate()\n\nWraps a date string to represent a BSON Date.",
            insertText: "ISODate(\"\")",
            cursorOffset: 9,
            isKey: false
        ),
        QueryCompletionItem(
            label: "NumberInt",
            kind: .bsonHelper,
            detail: "Constructs a 32-bit signed integer",
            documentation: "Syntax: NumberInt(number) or NumberInt(\"string\")\n\nExplicitly specifies a 32-bit integer in BSON.",
            insertText: "NumberInt()",
            cursorOffset: 10,
            isKey: false
        ),
        QueryCompletionItem(
            label: "NumberLong",
            kind: .bsonHelper,
            detail: "Constructs a 64-bit signed integer",
            documentation: "Syntax: NumberLong(number) or NumberLong(\"string\")\n\nHandles 64-bit integers exceeding standard JSON numbers.",
            insertText: "NumberLong(\"\")",
            cursorOffset: 12,
            isKey: false
        ),
        QueryCompletionItem(
            label: "NumberDecimal",
            kind: .bsonHelper,
            detail: "Constructs a 128-bit high-precision Decimal",
            documentation: "Syntax: NumberDecimal(\"0.0\")\n\nHigh-precision representation for financial and monetary calculations.",
            insertText: "NumberDecimal(\"\")",
            cursorOffset: 15,
            isKey: false
        ),
        QueryCompletionItem(
            label: "UUID",
            kind: .bsonHelper,
            detail: "Constructs a BSON UUID BinData subtype 4",
            documentation: "Syntax: UUID(\"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx\")",
            insertText: "UUID(\"\")",
            cursorOffset: 6,
            isKey: false
        ),
        QueryCompletionItem(
            label: "BinData",
            kind: .bsonHelper,
            detail: "Constructs a BSON binary data object",
            documentation: "Syntax: BinData(subtype, base64String)",
            insertText: "BinData(0, \"\")",
            cursorOffset: 12,
            isKey: false
        ),
        QueryCompletionItem(
            label: "Timestamp",
            kind: .bsonHelper,
            detail: "Constructs a BSON internal Timestamp",
            documentation: "Syntax: Timestamp(seconds, ordinal)",
            insertText: "Timestamp(0, 0)",
            cursorOffset: 12,
            isKey: false
        ),
        QueryCompletionItem(
            label: "MinKey",
            kind: .bsonHelper,
            detail: "Represents a minimum value for BSON comparisons",
            documentation: "Syntax: MinKey\n\nCompares lower than all other BSON types.",
            insertText: "MinKey",
            cursorOffset: 6,
            isKey: false
        ),
        QueryCompletionItem(
            label: "MaxKey",
            kind: .bsonHelper,
            detail: "Represents a maximum value for BSON comparisons",
            documentation: "Syntax: MaxKey\n\nCompares higher than all other BSON types.",
            insertText: "MaxKey",
            cursorOffset: 6,
            isKey: false
        ),
        QueryCompletionItem(
            label: "RegExp",
            kind: .bsonHelper,
            detail: "Constructs a regular expression object",
            documentation: "Syntax: RegExp(\"pattern\", \"flags\")",
            insertText: "RegExp(\"\", \"i\")",
            cursorOffset: 8,
            isKey: false
        )
    ]

    // MARK: - Aggregation Expressions / Operators

    static let aggregateOperators: [QueryCompletionItem] = [
        QueryCompletionItem(label: "$sum", kind: .aggregateOperator, detail: "Calculates the sum of numeric values"),
        QueryCompletionItem(label: "$avg", kind: .aggregateOperator, detail: "Calculates the average of numeric values"),
        QueryCompletionItem(label: "$first", kind: .aggregateOperator, detail: "Returns the first value from an array of documents"),
        QueryCompletionItem(label: "$last", kind: .aggregateOperator, detail: "Returns the last value from an array of documents"),
        QueryCompletionItem(label: "$min", kind: .aggregateOperator, detail: "Returns the minimum value"),
        QueryCompletionItem(label: "$max", kind: .aggregateOperator, detail: "Returns the maximum value"),
        QueryCompletionItem(label: "$concat", kind: .aggregateOperator, detail: "Concatenates strings into a single string"),
        QueryCompletionItem(label: "$cond", kind: .aggregateOperator, detail: "Ternary operator: if, then, else"),
        QueryCompletionItem(label: "$ifNull", kind: .aggregateOperator, detail: "Evaluates an expression and returns an alternative if null")
    ]
}
