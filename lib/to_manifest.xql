xquery version "1.0";
declare namespace mets = "http://www.loc.gov/METS/";
declare namespace mix = "http://www.loc.gov/mix/v20";
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
declare variable $IMAGE_SERVER as xs:string :=
  "http://libimages.princeton.edu/loris";
declare variable $IMAGE_CONTEXT as xs:string :=
  "http://iiif.io/api/image/2/context.json";
declare variable $IMAGE_PROFILE as xs:string :=
  "http://iiif.io/api/image/2/profiles/level2.json";

  
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

declare function local:stringify($s as xs:string) {
  concat( '"', $s, '"' )
};

declare function local:to_json_kv_str($key as xs:string, $value as xs:string) {
    concat('"', $key, '": ', local:stringify($value))
};

declare function local:to_json_kv_int($key as xs:string, $value as xs:string) {
    concat('"', $key, '": ', $value)
};

declare function local:to_json_kv_arr($key as xs:string, $value as xs:string) {
    concat('"', $key, '": ', $value)
};

declare function local:to_json_kv_obj($key as xs:string, $value as xs:string) {
    concat('"', $key, '": ', $value)
};

declare function local:objectify($k-vs as xs:string*) {
  concat( "{", string-join( $k-vs, ","), "}" )
};

declare function local:arrayify($objs as xs:string*) {
  concat( "[", string-join( $objs, ","), "]" )
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

declare function local:file-for-image-div($div as element())
as element() {
  let $mets as element() := $div/ancestor::mets:mets
  let $file-id as xs:string := string($div/mets:fptr/@FILEID)
  return $mets//mets:file[@ID eq $file-id]
};

declare function local:tech-for-image-div($div as element())
as element() {
  let $mets as element() := $div/ancestor::mets:mets
  let $admid as xs:string := string(local:file-for-image-div($div)/@ADMID)
  return $mets//mets:techMD[@ID eq $admid]
};

declare function local:height-for-image-div($div as element())
as xs:string {
  string(local:tech-for-image-div($div)//mix:imageHeight)
};

declare function local:width-for-image-div($div as element())
as xs:string {
  string(local:tech-for-image-div($div)//mix:imageWidth)
};

declare function local:pudl-urn-to-base-uri($urn as xs:string) 
as xs:string {
  let $escaped as xs:string := replace($urn, "/", "%2F")
  let $id as xs:string := replace($escaped, "urn:pudl:images:deliverable:", "")
  return concat($IMAGE_SERVER, '/', $id)
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
  let $props as xs:string+ := (
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
    )
  return local:objectify($props)
};

(:TODO:)
declare function local:metadata-from-mets($mets as document-node())
as xs:string {
  '[ { "TO":"DO" } ]'
};

(:~
 : TODO: need to account for Physical structmaps that only have a root
 : to bring up the correct viewer: fall back to RelatedObjects
 :)
declare function local:process-as-collection($mets as document-node(),
                                             $metadata as xs:string,
                                             $base-uri as xs:string,
                                             $coll-uri as xs:string) 
as xs:string {
  let $file-sec as element() := $mets//mets:fileSec
  let $manifests as xs:string+ :=
    (: TODO: Maybe rewrite this to use the physical if there is one, otherwise 
      use the RelatedObjects :)
    for $phys-vol as element() in $mets//mets:div[@TYPE = $VOLUME_TYPES]
    return local:manifest-from_div($phys-vol, $base-uri, (), $coll-uri )
    (: TODO: METADATA :)
  let $manifest_arr as xs:string := local:arrayify($manifests)
  return local:to_json_kv_arr("manifests", $manifest_arr)
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
  let $label as xs:string := string($phys-vol/@LABEL)
  let $sequences as xs:string* := local:sequences-from-div($phys-vol, $base-uri)
  let $structs as xs:string* := local:structs-from-div($phys-vol, $base-uri)
  let $props as xs:string+ := (
    local:to_json_kv_str("@id", $uri),
    local:to_json_kv_str("@type", "sc:Manifest"),
    local:to_json_kv_str("@label", $label),
    if ($metadata) then local:to_json_kv_arr("metadata", $metadata) else (),
    if ($collection-uri) then local:to_json_kv_str("within", $collection-uri) else (),
    if ($sequences) then local:to_json_kv_arr("sequences", $sequences) else (),
    if (count($structs) > 0) then local:to_json_kv_arr("structures", $structs) else ()
  )
  return local:objectify($props)
};

(:~
 : Note that despite the function name, this always (for now anyway) returns
 : an array of one sc:Sequence. 
 : 
 : TODO: Don't forget "non-paged" and "start" viewing hint on canvases
 :)
declare function local:sequences-from-div($phys-vol as element(),
                                          $base-uri as xs:string)
as xs:string {
  let $uri as xs:string := concat($base-uri, '/sequence/pages.json')
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
  let $props as xs:string+ := (
    local:to_json_kv_str("@id", $uri),
    local:to_json_kv_str("@type", "sc:Sequence"),
    local:to_json_kv_str("@label", $label),
    if ($dir) then local:to_json_kv_str("viewing_direction", $dir) else (),
    local:to_json_kv_str("viewing_hint", $viewing-hint),
    if ($canvases) then local:to_json_kv_arr("canvases", $canvases) else ()
  )
  return local:arrayify(local:objectify($props))
};

declare function local:canvases-from-div($phys-vol as element(), 
                                         $base-uri as xs:string)
as xs:string {
  let $canvases :=
    for $div as element() in $phys-vol//mets:div[./mets:fptr]
      let $canvas := local:canvas-from-div($div, $base-uri) 
      order by $div/@ORDER cast as xs:integer
      return $canvas
  return local:arrayify($canvases)
};

declare function local:canvas-from-div($div as element(), 
                                       $base-uri as xs:string)
as xs:string {
  let $label as xs:string := local:label-for-phys-div($div)
  let $canvas-segment as xs:string := string($div/mets:fptr/@FILEID)
  let $uri as xs:string := concat($base-uri, "/canvas/", $canvas-segment, ".json")
  let $images as xs:string := local:image-anno-from-div($div, $base-uri)
  let $props as xs:string+ := (
    local:to_json_kv_str("@id", $uri),
    local:to_json_kv_str("@type", "sc:Canvas"),
    local:to_json_kv_str("label", $label),
    local:to_json_kv_str("width", local:width-for-image-div($div)),
    local:to_json_kv_str("height", local:height-for-image-div($div)),
    local:to_json_kv_arr("images", $images)
  )
  return local:objectify($props)
};

(:~ 
 : Always returns a 1-member JSON Array
 :)
declare function local:image-anno-from-div($div as element(),
                                           $base-uri as xs:string)
as xs:string {
  let $file as element() := local:file-for-image-div($div)
  let $resource as xs:string := local:resource-from-file($file, $base-uri)
  let $props as xs:string+ := (
    local:to_json_kv_str("@type", "oa:Annotation"),
    local:to_json_kv_str("motivation", "sc:painting"),
    local:to_json_kv_obj("resource", $resource)
  )
  return local:arrayify(local:objectify($props))
};


declare function local:resource-from-file($file as element(),
                                          $base-uri as xs:string)
as xs:string {
  let $urn as xs:string := string($file/mets:FLocat/@xlink:href)
  let $base-uri as xs:string := local:pudl-urn-to-base-uri($urn)
  let $uri as xs:string := concat($base-uri, "/full/full/0/native.jpg")
  let $type as xs:string := "dctypes:Image"
  let $format as xs:string := "image/jpeg"
  let $service as xs:string := local:service-from-image-base-uri($base-uri)
  let $props as xs:string+ := (
    local:to_json_kv_str("@id", $uri),
    local:to_json_kv_str("@type", $type),
    local:to_json_kv_str("format", $format),
    local:to_json_kv_obj("service", $service)
  )
  return local:objectify($props)
};

declare function local:service-from-image-base-uri($base-uri as xs:string)
as xs:string {
  let $props as xs:string+ := (
    local:to_json_kv_str("@context", $IMAGE_CONTEXT),
    local:to_json_kv_str("profile", $IMAGE_PROFILE),
    local:to_json_kv_str("@id", $base-uri)
  )
  return local:objectify($props)
};

declare function local:structs-from-div($phys-vol as element(), 
                                        $base-uri as xs:string) 
as xs:string {
  let $mets := $phys-vol/ancestor::mets:mets
  let $struct-maps as element()* := (
    if ($phys-vol/@ID) then
      let $smlink as element() := $mets//mets:smLink[@xlink:from eq $phys-vol/@ID]
      return $mets//mets:div[@ID eq $smlink/@xlink:to]
    else
      $mets//mets:structMap[@TYPE eq 'Logical']/mets:div,
    $phys-vol
  )
  let $ranges as xs:string* := 
    for $struct-map as element() in $struct-maps
    return local:struct-map-to-range($struct-map, $base-uri)
  return local:arrayify($ranges)
};


declare function local:struct-map-to-range($struct-map as element(), 
                                           $base-uri as xs:string) 
as xs:string* {
  let $ranges as xs:string* := 
    for $div as element() at $i in $struct-map/descendant-or-self::mets:div[@LABEL]
    let $range-id as xs:string := string($div/@ID)
    let $uri as xs:string := concat($base-uri, '/range/', $range-id, '.json')
    let $label as xs:string := string($div/@LABEL)
    let $canvases as xs:string* := 
      for $canvas as element() in ($div/mets:div[@TYPE = ("LogicalMember")], $div/mets:fptr)
      let $canvas-id as xs:string := (string($canvas/mets:fptr/@FILEID), $canvas/@FILEID)[1] (: check this w/ eg. photo albums:)
      return local:stringify(concat($base-uri, '/canvas/', $canvas-id, '.json'))
    let $ranges as xs:string* :=
      for $range as element() in $div/mets:div[@LABEL]
      let $range-id as xs:string := string($div/@ID)
      return local:stringify(concat($base-uri, '/range/', $range-id, '.json'))
    let $props as xs:string+ := (
      local:to_json_kv_str("@id", $uri),
      local:to_json_kv_str("@type", "sc:Range"),
      if ($i = 1) then local:to_json_kv_str("viewing_hint", "top") else (), 
      local:to_json_kv_str("label", $label),
      if (count($canvases) > 0) then local:to_json_kv_arr("canvases", local:arrayify($canvases)) else (),
      if (count($ranges) > 0) then local:to_json_kv_arr("ranges", local:arrayify($ranges)) else ()
    )
    return local:objectify($props)
  return $ranges
};


(:~ Main :)
local:process-doc($doc-path)


(:~ Note: when we get to the "metadata", saxon:transform should help 
 : with the repurposing of XSLTs from the PUDL that, eg. turn high-level
 : MODS and VRA elements into strings.
 :)


(:
PUL mets:div @TYPEs:

AggregatedObject
Bifolio
Binding
BoundAlbum
BoundArt
BoundEntity
BoundFragment
BoundManuscript
BoundVolume
BoundWithVolume
Colophon
ContactSheet
Contents
CoverInside
CoverOutside
DisboundVolume
Drawing
FlipChart
Foiio
FoldedSheet
Folio
ForeEdge
Fragment
FragmentedLeaf
FrontMatter
FrontisPiece
Gathering
Insert
IsPartOf
Leaf
LogicalMember
LowerCover
MountedMap
MountedPhotograph
MultiVolumeSet
Object
OrderedList
Overture
Page
Panel
PasteDown
Pastedown
Plate
Polyptych
RTLBoundManuscript
RTLBoundVolume
RTLObject
Scroll
ScrollSet
Section
Sheet
Side
Static
TightBoundManuscript
TightRTLBoundManuscript
TitlePage
UnboundGroup
UpperCover
Volume
Work
Works
Wrapper
leaf
section:)
