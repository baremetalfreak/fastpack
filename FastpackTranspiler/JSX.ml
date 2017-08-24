let transpile program =
  let map_expression ((loc, node) : Ast.Expression.t) =
    let module E = Ast.Expression in
    let module I = Ast.Identifier in
    let open Ast.JSX in

    (** Transpile JSX elememnt name *)
    let transpile_name (name : name) =
      let aux_property ((loc, { name }) : Identifier.t) =
        (loc, name)
      in
      let rec aux_object (_object : MemberExpression._object) =
        match _object with
        | MemberExpression.Identifier (loc, { name }) ->
          E.Identifier (loc, name)
        | MemberExpression.MemberExpression (loc, { _object; property }) ->
          E.Member {
            _object = loc, aux_object _object;
            property = E.Member.PropertyIdentifier (aux_property property);
            computed = false;
          }
      in

      match name with
      | Identifier (loc, { name }) ->
        loc, E.Identifier (loc, name)
      | MemberExpression (loc, { _object; property }) ->
        loc, E.Member {
          _object = Loc.none, aux_object _object;
          property = E.Member.PropertyIdentifier (aux_property property);
          computed = false;
        }
      | NamespacedName _ ->
        failwith "Namespaced tags are not supported. ReactJSX is not XML"
    in

    (** Transpile JSX attributes *)
    let transpile_attributes (attributes : Opening.attribute list) =
      let null_expression = Loc.none, E.Literal { value = Ast.Literal.Null; raw = "null"; } in
      match attributes with
      (** If no attributes present we pass null *)
      | [] -> [E.Expression null_expression]
      | attributes ->
        let (bucket, expressions) = List.fold_left
            (fun (bucket, expressions) (attr : Opening.attribute) ->
               match attr with
               | Opening.Attribute (loc, { name; value }) ->
                 let key = match name with
                   | Attribute.Identifier (loc, { name }) ->
                     E.Object.Property.Literal (loc, { value = Ast.Literal.String name; raw = name })
                   | Attribute.NamespacedName _ ->
                     failwith "Namespaced tags are not supported. ReactJSX is not XML"
                 in
                 let value = match value with
                   | None ->
                     null_expression
                   | Some (Attribute.Literal (loc, lit)) ->
                     loc, E.Literal lit
                   | Some (Attribute.ExpressionContainer (_loc, { expression = ExpressionContainer.Expression expr })) ->
                     expr
                   | Some (Attribute.ExpressionContainer (_loc, { expression = ExpressionContainer.EmptyExpression _ })) ->
                     failwith "Found EmptyExpression container"
                 in
                 let prop = E.Object.Property (
                     loc,
                     { key; value = E.Object.Property.Init value; _method = false; shorthand = false }
                   ) in
                 (prop::bucket, expressions)
               | Opening.SpreadAttribute (loc, { argument }) ->
                 let expr = E.Expression (Loc.none, E.Object { properties = bucket }) in
                 let spread = E.Spread (loc, { E.SpreadElement. argument }) in
                 ([], spread::expr::expressions))
            ([], [])
            attributes
        in
        let expressions = match bucket with
          | [] ->
            expressions
          | bucket -> 
            let expr = E.Expression (Loc.none, E.Object { properties = bucket }) in
            expr::expressions
        in
        expressions
    in

    let node = match node with
      | E.JSXElement {
          openingElement = (_, openingElement);
          closingElement = _;
          children = _
        } ->
        let { Opening. name; attributes; _ } = openingElement in
        E.Call {
          callee = Loc.none, E.Member {
              computed = false;
              _object = Loc.none, E.Identifier (Loc.none, "React");
              property = E.Member.PropertyIdentifier (Loc.none, "createElement");
            };
          arguments = (E.Expression (transpile_name name))::(transpile_attributes attributes)
        }

      | node -> node
    in
    (loc, node)
  in

  let mapper = {
    AstMapper.default_mapper with
    map_expression;
  } in

  AstMapper.map mapper program
