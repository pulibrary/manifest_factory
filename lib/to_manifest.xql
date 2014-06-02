xquery version "1.0";
declare namespace mets = "http://www.loc.gov/METS/";
declare namespace mods = "http://www.loc.gov/mods/v3";
declare namespace xlink = "http://www.w3.org/1999/xlink";

declare option saxon:output "omit-xml-declaration=yes";

(:~ External - set this to a file to debug :)
declare variable $doc-path external;
(:declare variable $doc-path := "../sample_data/3013164.mets";:)

(:~ Constants :)
declare variable $CONTEXT as xs:string := 
  "http://iiif.io/api/presentation/2/context.json";
declare variable $BASE as xs:string := 
  "http://library.princeton.edu/iiif";
  
declare variable $COLL_TYPES as xs:string+ := (
 "MultiVolumeSet"
);

declare variable $VOLUME_TYPES as xs:string+ := (
  "BoundVolume",
  "RTLBoundVolume"
);

declare variable $PAGED_TYPES as xs:string+ := (
  "BoundVolume",
  "RTLBoundVolume"
);

declare variable $THUMBED_TYPES as xs:string+ := (
  "BoundArt"
);


(:~ Functions: Helpers :)

declare function local:title-from-mets($mets as document-node()) 
as xs:string {
  subsequence($mets//mods:title, 1, 1)/string()
  (: TODO: more logic here    :)
};

declare function local:to_json_kv_str($key as xs:string, $value as xs:string) {
    concat('"', $key, '": "', $value, '"')
};

declare function local:to_json_kv_int($key as xs:string, $value as xs:string) {
    concat('"', $key, '": ', $value)
};

declare function local:to_json_kv_arr($key as xs:string, $value as xs:string) {
    concat('"', $key, '": ', $value)
};

declare function local:mf-type-from-mets($mets as document-node()) 
as xs:string {
  if (string($mets//mets:structMap[@TYPE eq "Physical"]/mets:div/@TYPE) = $COLL_TYPES) 
  then "sc:Collection"
  else "sc:Manifest"
};

declare function local:label-for-phys-div($div as element()) 
as xs:string {
    string-join(subsequence($div/ancestor-or-self::mets:div/@LABEL, 2),', ')
};

declare function local:uri-segement-for-phys-div($div as element())
as xs:string {
  let $label := local:label-for-phys-div($div)
  return lower-case(replace($label, "[^\p{L}\p{N}]", ""))
};


(:~ Functions: Builders :)

declare function local:process-doc($path as xs:string) {
    let $doc as document-node():= doc($path)
    return local:root($doc)
};

declare function local:root($mets as document-node()) 
as xs:string {
  let $type as xs:string := local:mf-type-from-mets($mets)
  let $base-uri as xs:string := concat($BASE, "/", string($mets/mets:mets/@OBJID))
  let $uri as xs:string := 
    if ($type eq "sc:Manifest") then 
      concat($base-uri, '/manifest.json')
    else concat($base-uri, '/collection.json')
  let $label as xs:string := local:title-from-mets($mets)
  (: TODO: Metadata :)
  let $metadata as xs:string := local:metadata-from-mets($mets)
  return concat( 
    "{",
    string-join((
      local:to_json_kv_str("@context", $CONTEXT),
      local:to_json_kv_str("@id", $uri),
      local:to_json_kv_str("@type", $type),
      local:to_json_kv_str("@label", $label),
      local:to_json_kv_arr("metadata", $metadata),
      if ($type eq "sc:Manifest") then 
        (: TODO: UNTESTED :)
        let $div as element() := $mets//mets:div[@ID eq 'aggregates']
        return local:manifest-from_div($div, $base-uri, $metadata, ())
      else
        local:process-as-collection($mets, $metadata, $base-uri, $uri)
    ), ","),
    "}"  
  )    
};

(:TODO:)
declare function local:metadata-from-mets($mets as document-node())
as xs:string {
  '[ { "TO":"DO" } ]'
};

declare function local:process-as-collection($mets as document-node(),
                                             $metadata as xs:string,
                                             $base-uri as xs:string,
                                             $coll-uri as xs:string) 
as xs:string {
  let $file-sec as element() := $mets//mets:fileSec
  let $manifests as xs:string+ :=
    for $phys-vol as element() in $mets//mets:div[@TYPE = $VOLUME_TYPES]
    return local:manifest-from_div($phys-vol, $base-uri, (), $coll-uri )
    (: TODO: METADATA :)
  return concat('"manifests": [', string-join($manifests, ","), ']')
};

(:~
 : Make a manifest from a div.  
 :)
declare function local:manifest-from_div($phys-vol as element(),
                                         $base-uri as xs:string,
                                         $metadata as xs:string?,
                                         $collection-uri as xs:string?)
as xs:string+ {
  let $base-uri as xs:string := concat($base-uri, '/', string($phys-vol/@ID))
  let $uri as xs:string := concat($base-uri, '/manifest.json')
  let $type as xs:string := "sc:Manifest"
  let $label as xs:string := string($phys-vol/@LABEL)
  let $sequences as xs:string* := local:sequences-from-div($phys-vol, $base-uri)
  return concat( 
    "{",
    string-join((
      local:to_json_kv_str("@id", $uri),
      local:to_json_kv_str("@type", $type),
      local:to_json_kv_str("@label", $label),
      if ($metadata) then local:to_json_kv_arr("metadata", $metadata) else (),
      if ($collection-uri) then local:to_json_kv_str("within", $collection-uri) else (),
      if ($sequences) then local:to_json_kv_arr("sequences", $sequences) else ()
    ), ","),
    "}"
  )
};

(:~
 : Note that despite the function name, this always (for now anyway) returns
 : an array of one sc:Sequence. 
 : 
 : TODO: Should also account for the case where the volume has no children, in 
 : which case we should go to the fileSec (Lapidus, maybe others?). May need
 : the mets:structLink to make it so :-(
 :
 : TODO: Don't forget "non-paged" and "start" viewing hint on canvases
 :)
declare function local:sequences-from-div($phys-vol as element(),
                                          $base-uri as xs:string)
as xs:string {
  let $uri as xs:string := concat($base-uri, '/sequence/pages.json')
  (: note that we don't modify the base uri here :)
  let $type as xs:string := "sc:Sequence"
  let $label as xs:string := "Page Sequence" (: ?? :)
  let $viewing-hint as xs:string :=
    (: TODO: more logic here: "individuals", "paged", "continuous" :)
    if (string($phys-vol/@TYPE) = $PAGED_TYPES) then
      "paged"
    else "individuals"
  let $dir as xs:string? := 
    if ($viewing-hint eq "paged") then
      if (starts-with(string($phys-vol/@TYPE), "RTL")) then
        "right-to-left"
      else "left-to-right"
    else ()
  let $canvases as xs:string := local:canvases-from-div($phys-vol, $base-uri)  
  return concat( 
    "[{",
    string-join((
      local:to_json_kv_str("@id", $uri),
      local:to_json_kv_str("@type", $type),
      local:to_json_kv_str("@label", $label),
      if ($dir) then local:to_json_kv_str("viewing_direction", $dir) else (),
      local:to_json_kv_str("viewing_hint", $viewing-hint),
      if ($canvases) then local:to_json_kv_arr("canvases", $canvases) else ()
    ), ","),
    "}]"
  )
};

declare function local:canvases-from-div($phys-vol as element(), 
                                         $base-uri as xs:string)
as xs:string {
  let $canvases :=
    for $div as element() in $phys-vol//mets:div[./mets:fptr]
      let $canvas := local:canvas-from-div($div, $base-uri) 
      order by $div/@ORDER cast as xs:integer
      return $canvas
  return concat('[', string-join($canvases, ","), ']')
};

declare function local:canvas-from-div($div as element(), 
                                       $base-uri as xs:string)
as xs:string {
  let $label as xs:string := local:label-for-phys-div($div)
  let $canvas-segment as xs:string := string($div/mets:fptr/@FILEID)
  let $uri as xs:string := concat($base-uri, "/canvas/", $canvas-segment, ".json")
  let $type as xs:string := "sc:Canvas"
  
  return concat( "{",
    string-join((
      local:to_json_kv_str("@id", $uri),
      local:to_json_kv_str("@type", $type),
      local:to_json_kv_str("label", $label)
    ), ","),
  "}"
  )
  
  

};


(:~ Main :)
local:process-doc($doc-path)


(:~ Note: when we get to the "metadata", saxon:transform should help 
 : with the repurposing of XSLTs from the PUDL that, eg. turn high-level
 : MODS and VRA elements into strings.
 :)
