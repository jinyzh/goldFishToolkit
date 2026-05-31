/***********************************************************************
 * goldFishToolkit_clean_full.il
 *
 * Clean single-file version for Cadence Virtuoso Layout Editor.
 *
 * Features:
 *   1. Hierarchical Pin Refill
 *      - Recursively scan hierarchy instances.
 *      - Copy each instance master's terminal pin figures to current top
 *        layout as normal drawing shapes.
 *      - Generated shapes are tagged by property and can be deleted later.
 *
 *   2. Current-Level Grid Utilities
 *      - Select Off-Grid Objects:
 *          current-level instances: check instance GUI origin / transform origin
 *          current-level shapes   : check real geometry
 *          no hierarchy descent
 *      - Snap Selected to Grid:
 *          instances: move origin only
 *          rects    : snap bbox LL and UR
 *          polygons : snap every vertex
 *          paths    : snap every point and width
 *          pathSeg  : snap begin/end and width, recreated as path
 *
 *   3. Clear Steiners / BBox Fix
 *      - Delete current edit cellView steiners.
 *
 *   4. Create Stair Line
 *      - GUI utility to create a stair/step polygon and paste it interactively.
 *
 *   5. Menu / Bindkey
 *      - Layout Editor -> goldFishToolkit
 *      - Optional bindkey: Layout <Key>% -> gfStairLineGUI()
 *
 ***********************************************************************/


/***********************************************************************
 * Global Settings
 ***********************************************************************/

; ===== Hierarchical Pin Refill Settings =====

gfPinRefillPurpose = "drawing"
gfPinRefillPropName = "goldFish_emx_pin_refill"

; nil means copy all allowed pin layers.
; Example:
; gfPinRefillLayerFilter = '("M1" "M2" "M3" "M4" "M5" "M6" "TM" "AP" "RDL")
gfPinRefillLayerFilter = nil

gfPinRefillExcludeLayers = '("text" "TEXT" "annotate" "ANNOTATE" "marker" "MARKER")

; nil means copy pins from all instance libraries.
; If only PDK device pins are needed:
; gfPinRefillLibFilter = '("your_pdk_lib")
gfPinRefillLibFilter = nil

gfAutoDeleteOldRefill = t
gfMaxHierDepth = 64

; ===== Grid Settings =====

gfSnapGrid = 0.005
gfOffGridTol = 1e-12
gfMoveInstancesToGrid = t
gfSnapShapeGeometryToGrid = t

; ===== Stair Line Settings =====

gfStairLineDefaultLongSide   = 70.0
gfStairLineDefaultShortSide  = 10.0
gfStairLineDefaultLineLength = 400.0
gfStairLineDefaultStep       = 6
gfStairLinePlaceByPaste      = t
gfInstallStairLineBindKey    = t
gfStairLineBindKey           = "<Key>%"

gfStairLineTargetWin = nil
gfStairLineTargetCV  = nil

; ===== Menu Settings =====

gfMenuPosition = 8

; ===== Debug =====

gfVerbose = t


/***********************************************************************
 * Basic Utilities
 ***********************************************************************/

procedure(gfCurrentLayoutCV()
  let((cv)
    cv = geGetEditCellView()

    unless(cv
      error("goldFishToolkit: no current edit cellView found. Open/activate a layout window first.\n")
    )

    unless(cv~>cellViewType == "maskLayout"
      warn("goldFishToolkit: current cellViewType is %L, expected maskLayout. Continue anyway.\n"
           cv~>cellViewType)
    )

    cv
  )
)


procedure(gfPtX(pt)
  let((r)
    cond(
      ((null pt) nil)
      ((listp pt) car(pt))
      (t
        r = errset(xCoord(pt) nil)
        if(r then car(r) else nil)
      )
    )
  )
)


procedure(gfPtY(pt)
  let((r)
    cond(
      ((null pt) nil)
      ((listp pt) cadr(pt))
      (t
        r = errset(yCoord(pt) nil)
        if(r then car(r) else nil)
      )
    )
  )
)


procedure(gfMakePt(x y)
  x:y
)


procedure(gfRoundToGrid(val grid)
  grid * round(val / grid)
)


procedure(gfPointToGrid(pt grid)
  gfMakePt(
    gfRoundToGrid(gfPtX(pt) grid)
    gfRoundToGrid(gfPtY(pt) grid)
  )
)


procedure(gfPointOnGridP(pt grid tol)
  let((x y ok)
    ok = nil

    when(pt && grid && grid > 0
      x = gfPtX(pt)
      y = gfPtY(pt)

      when(x && y
        ok = ((abs(x - gfRoundToGrid(x grid)) <= tol) &&
              (abs(y - gfRoundToGrid(y grid)) <= tol))
      )
    )

    ok
  )
)


procedure(gfPointOffGridP(pt grid tol)
  !gfPointOnGridP(pt grid tol)
)


procedure(gfPointsEqualP(p1 p2 tol)
  when(p1 && p2
    (abs(gfPtX(p1) - gfPtX(p2)) <= tol) &&
    (abs(gfPtY(p1) - gfPtY(p2)) <= tol)
  )
)


procedure(gfStringMemberP(str strList)
  let((found)
    found = nil

    foreach(item strList
      when(equal(str item)
        found = t
      )
    )

    found
  )
)


procedure(gfObjType(obj)
  let((r)
    r = errset(obj~>objType nil)
    if(r then car(r) else nil)
  )
)


procedure(gfInstP(obj)
  equal(gfObjType(obj) "inst")
)


procedure(gfBBox(obj)
  let((r)
    r = errset(obj~>bBox nil)
    if(r then car(r) else nil)
  )
)


procedure(gfBBoxLL(bBox)
  car(bBox)
)


procedure(gfBBoxUR(bBox)
  cadr(bBox)
)


procedure(gfShapeAllowedP(obj)
  let((typ)
    typ = gfObjType(obj)

    (equal(typ "rect") ||
     equal(typ "polygon") ||
     equal(typ "boundary") ||
     equal(typ "path") ||
     equal(typ "pathSeg"))
  )
)


procedure(gfLPP(fig)
  let((r layer purpose lpp)
    lpp = nil

    r = errset(fig~>lpp nil)
    when(r && car(r)
      lpp = car(r)
    )

    unless(lpp
      layer = nil
      purpose = nil

      r = errset(fig~>layerName nil)
      when(r
        layer = car(r)
      )

      r = errset(fig~>purposeName nil)
      when(r
        purpose = car(r)
      )

      unless(purpose
        r = errset(fig~>purpose nil)
        when(r
          purpose = car(r)
        )
      )

      unless(purpose
        purpose = "drawing"
      )

      lpp = list(layer purpose)
    )

    lpp
  )
)


procedure(gfDeselectAll()
  errset(geDeselectAllFig() t)
  errset(geDeselectAll() t)
  t
)


procedure(gfSelectObjectSafe(obj)
  let((ok)
    ok = nil

    when(obj
      ok = errset(geSelectObject(obj) t)
      unless(ok
        ok = errset(geSelectFig(obj) t)
      )
    )

    ok
  )
)


procedure(gfCopyProps(src dst)
  let((props)
    when(src && dst
      props = nil
      errset(props = src~>prop nil)

      foreach(prop props
        errset(
          dbCreateProp(dst prop~>name prop~>valueType prop~>value)
          nil
        )
      )
    )

    dst
  )
)


procedure(gfMoveFigByDelta(fig cv dx dy)
  let((ok)
    ok = nil

    when(fig && cv
      ok = errset(
        dbMoveFig(fig cv list(gfMakePt(dx dy) "R0" 1.0))
        t
      )

      unless(ok
        ok = errset(
          dbMoveFig(fig list(gfMakePt(dx dy) "R0" 1.0))
          t
        )
      )
    )

    ok
  )
)


procedure(gfPrintSettings()
  printf("\n")
  printf("=============== goldFishToolkit Settings ===============\n")
  printf("gfPinRefillPurpose        = %L\n" gfPinRefillPurpose)
  printf("gfPinRefillPropName       = %L\n" gfPinRefillPropName)
  printf("gfPinRefillLayerFilter    = %L\n" gfPinRefillLayerFilter)
  printf("gfPinRefillExcludeLayers  = %L\n" gfPinRefillExcludeLayers)
  printf("gfPinRefillLibFilter      = %L\n" gfPinRefillLibFilter)
  printf("gfAutoDeleteOldRefill     = %L\n" gfAutoDeleteOldRefill)
  printf("gfMaxHierDepth            = %L\n" gfMaxHierDepth)
  printf("gfSnapGrid                = %L\n" gfSnapGrid)
  printf("gfOffGridTol              = %L\n" gfOffGridTol)
  printf("gfMoveInstancesToGrid     = %L\n" gfMoveInstancesToGrid)
  printf("gfSnapShapeGeometryToGrid = %L\n" gfSnapShapeGeometryToGrid)
  printf("gfVerbose                 = %L\n" gfVerbose)
  printf("=========================================================\n")
  printf("\n")
)


/***********************************************************************
 * Hierarchical Pin Refill
 ***********************************************************************/

gfRefillStatInstScanned = 0
gfRefillStatInstCopied  = 0
gfRefillStatFigCopied   = 0
gfRefillStatSkipped     = 0


procedure(gfResetRefillStats()
  gfRefillStatInstScanned = 0
  gfRefillStatInstCopied  = 0
  gfRefillStatFigCopied   = 0
  gfRefillStatSkipped     = 0
)


procedure(gfPinLayerAllowedP(layerName)
  let((ok)
    ok = t

    unless(layerName
      ok = nil
    )

    when(ok && gfPinRefillLayerFilter
      ok = gfStringMemberP(layerName gfPinRefillLayerFilter)
    )

    when(ok && gfStringMemberP(layerName gfPinRefillExcludeLayers)
      ok = nil
    )

    ok
  )
)


procedure(gfInstLibAllowedP(inst)
  let((libName ok)
    ok = t

    when(gfPinRefillLibFilter
      ok = nil

      when(inst && inst~>master && inst~>master~>libName
        libName = inst~>master~>libName
        ok = gfStringMemberP(libName gfPinRefillLibFilter)
      )
    )

    ok
  )
)


procedure(gfBuildInstPath(parentPath instName)
  let((name)
    name = instName
    unless(name
      name = "<unnamed>"
    )

    if(parentPath && parentPath != "" then
      strcat(parentPath "/" name)
    else
      name
    )
  )
)


procedure(gfXformMag(xform)
  let((mag)
    mag = 1.0

    when(listp(xform) && length(xform) >= 3
      mag = caddr(xform)
    )

    unless(mag
      mag = 1.0
    )

    mag
  )
)


procedure(gfXformPathMag(xformPath)
  let((mag)
    mag = 1.0

    foreach(xf xformPath
      mag = mag * gfXformMag(xf)
    )

    mag
  )
)


procedure(gfTransformPointByPath(pt xformPath)
  let((newPt)
    newPt = pt

    foreach(xf xformPath
      newPt = dbTransformPoint(newPt xf)
    )

    newPt
  )
)


procedure(gfTransformBBoxByPath(bBox xformPath)
  let((newBBox)
    newBBox = bBox

    foreach(xf xformPath
      newBBox = dbTransformBBox(newBBox xf)
    )

    newBBox
  )
)


procedure(gfTransformPointListByPath(ptList xformPath)
  foreach(mapcar pt ptList
    gfTransformPointByPath(pt xformPath)
  )
)


procedure(gfRefillFigP(fig)
  let((ok r)
    ok = nil

    when(fig
      r = errset(dbFindProp(fig gfPinRefillPropName) nil)
      when(r && car(r)
        ok = t
      )

      unless(ok
        errset(
          when(fig~>goldFish_emx_pin_refill
            ok = t
          )
          nil
        )
      )
    )

    ok
  )
)


procedure(gfMarkRefillFig(fig instPath instName termName srcLib srcCell srcView)
  when(fig
    errset(dbCreateProp(fig gfPinRefillPropName "string" "t") nil)
    errset(dbCreateProp(fig "goldFish_refill_hierPath" "string" instPath) nil)
    errset(dbCreateProp(fig "goldFish_refill_inst"     "string" instName) nil)
    errset(dbCreateProp(fig "goldFish_refill_term"     "string" termName) nil)
    errset(dbCreateProp(fig "goldFish_refill_srcLib"   "string" srcLib) nil)
    errset(dbCreateProp(fig "goldFish_refill_srcCell"  "string" srcCell) nil)
    errset(dbCreateProp(fig "goldFish_refill_srcView"  "string" srcView) nil)
  )

  fig
)


procedure(gfCopyPinFigToTop(srcFig topCv xformPath instPath instName termName srcLib srcCell srcView)
  let((objType layerName newLpp newFig newBBox newPts newWidth pathMag)
    newFig = nil

    if(srcFig then
      objType = srcFig~>objType
      layerName = srcFig~>layerName

      if(layerName then
        when(gfPinLayerAllowedP(layerName)
          newLpp = list(layerName gfPinRefillPurpose)
          pathMag = gfXformPathMag(xformPath)

          cond(
            ((equal objType "rect")
              newBBox = gfTransformBBoxByPath(srcFig~>bBox xformPath)
              newFig = dbCreateRect(topCv newLpp newBBox)
            )

            ((or (equal objType "polygon") (equal objType "boundary"))
              newPts = gfTransformPointListByPath(srcFig~>points xformPath)
              newFig = dbCreatePolygon(topCv newLpp newPts)
            )

            ((equal objType "path")
              newPts = gfTransformPointListByPath(srcFig~>points xformPath)
              newWidth = srcFig~>width * pathMag
              newFig = dbCreatePath(topCv newLpp newPts newWidth)
            )

            ((equal objType "pathSeg")
              newPts = list(
                gfTransformPointByPath(srcFig~>beginPt xformPath)
                gfTransformPointByPath(srcFig~>endPt   xformPath)
              )
              newWidth = srcFig~>width * pathMag
              newFig = dbCreatePath(topCv newLpp newPts newWidth)
            )

            (t
              gfRefillStatSkipped = gfRefillStatSkipped + 1
              when(gfVerbose
                printf("goldFishToolkit: skip unsupported pin fig type %s on layer %s, path=%s, term=%s\n"
                       objType layerName instPath termName)
              )
            )
          )

          when(newFig
            gfRefillStatFigCopied = gfRefillStatFigCopied + 1
            gfMarkRefillFig(newFig instPath instName termName srcLib srcCell srcView)

            when(gfVerbose
              printf("goldFishToolkit: refill %s/%s, path=%s, term=%s, type=%s\n"
                     layerName gfPinRefillPurpose instPath termName objType)
            )
          )
        )
      else
        gfRefillStatSkipped = gfRefillStatSkipped + 1
      )
    )

    newFig
  )
)


procedure(gfCopyOneInstTerminalPins(inst topCv xformPath instPath)
  let((masterCv count instName srcLib srcCell srcView)
    count = 0

    when(inst && equal(inst~>objType "inst")
      masterCv = inst~>master
      instName = inst~>name

      unless(instName
        instName = "<unnamed>"
      )

      if(masterCv then
        when(gfInstLibAllowedP(inst)
          srcLib  = masterCv~>libName
          srcCell = masterCv~>cellName
          srcView = masterCv~>viewName

          foreach(term masterCv~>terminals
            foreach(pin term~>pins
              foreach(fig pin~>figs
                when(gfCopyPinFigToTop(fig topCv xformPath instPath instName term~>name srcLib srcCell srcView)
                  count = count + 1
                )
              )
            )
          )

          when(count > 0
            gfRefillStatInstCopied = gfRefillStatInstCopied + 1
          )
        )
      else
        warn("goldFishToolkit: instance %s has no master, skipped.\n" instPath)
      )
    )

    count
  )
)


procedure(gfRefillOneInstHier(inst topCv parentXformPath parentInstPath depth)
  let((masterCv xformPath instPath count childCount)
    count = 0

    when(inst && equal(inst~>objType "inst")
      gfRefillStatInstScanned = gfRefillStatInstScanned + 1

      if(gfMaxHierDepth && depth > gfMaxHierDepth then
        warn("goldFishToolkit: max hierarchy depth exceeded at %s. Recursion stopped.\n" parentInstPath)
      else
        masterCv = inst~>master

        if(masterCv then
          instPath = gfBuildInstPath(parentInstPath inst~>name)

          ; Transform path order is leaf -> parent -> ... -> top.
          xformPath = cons(inst~>transform parentXformPath)

          ; Copy this instance master's terminal pin figures to top.
          count = count + gfCopyOneInstTerminalPins(inst topCv xformPath instPath)

          ; Recurse through all cells. The library filter controls copying only,
          ; not traversal.
          when(masterCv~>cellViewType == "maskLayout"
            foreach(child masterCv~>instances
              when(child && equal(child~>objType "inst")
                childCount = gfRefillOneInstHier(child topCv xformPath instPath depth + 1)
                count = count + childCount
              )
            )
          )
        else
          warn("goldFishToolkit: instance %s has no master, skipped.\n" inst~>name)
        )
      )
    )

    count
  )
)


procedure(gfDeleteRefillPins(@optional (cv gfCurrentLayoutCV()))
  let((delCount figsToDelete)
    delCount = 0
    figsToDelete = nil

    foreach(fig cv~>shapes
      when(gfRefillFigP(fig)
        figsToDelete = cons(fig figsToDelete)
      )
    )

    foreach(fig figsToDelete
      when(fig && fig~>cellView
        dbDeleteObject(fig)
        delCount = delCount + 1
      )
    )

    printf("goldFishToolkit: deleted %d generated refill shapes.\n" delCount)
    delCount
  )
)


procedure(gfPrintRefillSummary(total)
  printf("goldFishToolkit: hierarchical pin refill finished.\n")
  printf("  instances scanned         : %d\n" gfRefillStatInstScanned)
  printf("  instances with pins copied: %d\n" gfRefillStatInstCopied)
  printf("  shapes generated          : %d\n" total)
  printf("  unsupported/skipped figs  : %d\n" gfRefillStatSkipped)
)


procedure(gfRefillSelectedPins(@optional (cv gfCurrentLayoutCV()))
  let((selSet total topInstCount n)
    selSet = geGetSelSet()
    total = 0
    topInstCount = 0

    when(gfAutoDeleteOldRefill
      gfDeleteRefillPins(cv)
    )

    gfResetRefillStats()

    foreach(obj selSet
      when(equal(gfObjType(obj) "inst")
        topInstCount = topInstCount + 1
        n = gfRefillOneInstHier(obj cv nil "" 0)
        total = total + n
      )
    )

    if(topInstCount == 0 then
      printf("goldFishToolkit: no top-level instance selected.\n")
    else
      printf("goldFishToolkit: selected hierarchy refill: %d selected top instances.\n" topInstCount)
      gfPrintRefillSummary(total)
    )

    total
  )
)


procedure(gfRefillAllPins(@optional (cv gfCurrentLayoutCV()))
  let((total topInstCount n)
    total = 0
    topInstCount = 0

    when(gfAutoDeleteOldRefill
      gfDeleteRefillPins(cv)
    )

    gfResetRefillStats()

    foreach(inst cv~>instances
      when(equal(gfObjType(inst) "inst")
        topInstCount = topInstCount + 1
        n = gfRefillOneInstHier(inst cv nil "" 0)
        total = total + n
      )
    )

    printf("goldFishToolkit: all hierarchy refill: %d top-level instances.\n" topInstCount)
    gfPrintRefillSummary(total)

    total
  )
)


/***********************************************************************
 * Current-Level Off-Grid / Snap to Grid
 ***********************************************************************/

procedure(gfInstTransform(inst)
  let((r)
    r = errset(inst~>transform nil)
    if(r then car(r) else nil)
  )
)


procedure(gfInstOrigin(inst)
  let((xf r pt)
    pt = nil

    ; GUI Origin is usually transform[0].
    xf = gfInstTransform(inst)

    when(xf && listp(xf)
      pt = car(xf)
    )

    unless(pt
      r = errset(inst~>xy nil)
      when(r && car(r)
        pt = car(r)
      )
    )

    unless(pt
      r = errset(inst~>origin nil)
      when(r && car(r)
        pt = car(r)
      )
    )

    pt
  )
)


procedure(gfInstOrient(inst)
  let((xf)
    xf = gfInstTransform(inst)

    if(xf && listp(xf) && cadr(xf) then
      cadr(xf)
    else
      "R0"
    )
  )
)


procedure(gfInstMag(inst)
  let((xf)
    xf = gfInstTransform(inst)

    if(xf && listp(xf) && caddr(xf) then
      caddr(xf)
    else
      1.0
    )
  )
)


procedure(gfInstName(inst)
  let((r)
    r = errset(inst~>name nil)
    if(r then car(r) else nil)
  )
)


procedure(gfInstLibCell(inst)
  let((master lib cell r)
    master = nil
    lib = nil
    cell = nil

    r = errset(inst~>master nil)
    when(r
      master = car(r)
    )

    when(master
      r = errset(master~>libName nil)
      when(r
        lib = car(r)
      )

      r = errset(master~>cellName nil)
      when(r
        cell = car(r)
      )
    )

    list(lib cell)
  )
)


procedure(gfWidthOffGridP(width grid tol)
  when(width
    abs(width - gfRoundToGrid(width grid)) > tol
  )
)


procedure(gfRoundWidth(width grid)
  let((newWidth)
    newWidth = gfRoundToGrid(width grid)

    when(newWidth <= 0
      newWidth = grid
    )

    newWidth
  )
)


procedure(gfPointListChangedP(oldPts newPts tol)
  let((changed oldRest newRest)
    changed = nil
    oldRest = oldPts
    newRest = newPts

    while(oldRest && newRest
      unless(gfPointsEqualP(car(oldRest) car(newRest) tol)
        changed = t
      )

      oldRest = cdr(oldRest)
      newRest = cdr(newRest)
    )

    when(oldRest || newRest
      changed = t
    )

    changed
  )
)


procedure(gfBBoxChangedP(oldBBox newBBox tol)
  !(gfPointsEqualP(car(oldBBox) car(newBBox) tol) &&
    gfPointsEqualP(cadr(oldBBox) cadr(newBBox) tol))
)


procedure(gfObjectOffGridP(obj grid @optional (tol gfOffGridTol))
  let((typ bBox pts width off origin)
    typ = gfObjType(obj)
    off = nil

    cond(
      ((equal typ "inst")
        origin = gfInstOrigin(obj)
        when(origin && gfPointOffGridP(origin grid tol)
          off = t
        )
      )

      ((equal typ "rect")
        bBox = gfBBox(obj)
        when(bBox
          when(gfPointOffGridP(car(bBox) grid tol) ||
               gfPointOffGridP(cadr(bBox) grid tol)
            off = t
          )
        )
      )

      ((or (equal typ "polygon") (equal typ "boundary"))
        pts = obj~>points
        foreach(pt pts
          when(gfPointOffGridP(pt grid tol)
            off = t
          )
        )
      )

      ((equal typ "path")
        pts = obj~>points
        foreach(pt pts
          when(gfPointOffGridP(pt grid tol)
            off = t
          )
        )

        width = obj~>width
        when(gfWidthOffGridP(width grid tol)
          off = t
        )
      )

      ((equal typ "pathSeg")
        when(gfPointOffGridP(obj~>beginPt grid tol)
          off = t
        )

        when(gfPointOffGridP(obj~>endPt grid tol)
          off = t
        )

        width = obj~>width
        when(gfWidthOffGridP(width grid tol)
          off = t
        )
      )
    )

    off
  )
)


procedure(gfSelectOffGridObjects(@optional (cv gfCurrentLayoutCV()) (grid gfSnapGrid))
  let((checkedInst checkedShape found selected libCell origin)
    checkedInst = 0
    checkedShape = 0
    found = 0
    selected = 0

    unless(grid && grid > 0
      error("goldFishToolkit: invalid gfSnapGrid = %L\n" grid)
    )

    gfDeselectAll()

    ; Current-level instances only. No hierarchy descent.
    foreach(inst cv~>instances
      when(inst && gfInstP(inst)
        checkedInst = checkedInst + 1

        when(gfObjectOffGridP(inst grid gfOffGridTol)
          found = found + 1

          when(gfVerbose
            libCell = gfInstLibCell(inst)
            origin = gfInstOrigin(inst)

            printf("goldFishToolkit: off-grid instance name=%L lib/cell=%L/%L origin=%L\n"
                   gfInstName(inst) car(libCell) cadr(libCell) origin)
          )

          when(gfSelectObjectSafe(inst)
            selected = selected + 1
          )
        )
      )
    )

    ; Current-level standalone shapes only. No hierarchy descent.
    foreach(obj cv~>shapes
      when(gfShapeAllowedP(obj)
        checkedShape = checkedShape + 1

        when(gfObjectOffGridP(obj grid gfOffGridTol)
          found = found + 1

          when(gfVerbose
            printf("goldFishToolkit: off-grid standalone shape type=%s lpp=%L bbox=%L\n"
                   gfObjType(obj) gfLPP(obj) gfBBox(obj))
          )

          when(gfSelectObjectSafe(obj)
            selected = selected + 1
          )
        )
      )
    )

    printf("goldFishToolkit: select off-grid objects finished: checkedInst=%d, checkedShape=%d, found=%d, selected=%d, grid=%L, tol=%L\n"
           checkedInst checkedShape found selected grid gfOffGridTol)

    selected
  )
)


procedure(gfMoveInstOriginToGrid(inst grid tol)
  let((origin newOrigin dx dy orient mag ok result)
    result = nil

    if(gfMoveInstancesToGrid then
      origin = gfInstOrigin(inst)

      if(origin then
        newOrigin = gfPointToGrid(origin grid)

        dx = gfPtX(newOrigin) - gfPtX(origin)
        dy = gfPtY(newOrigin) - gfPtY(origin)

        if((abs(dx) <= tol) && (abs(dy) <= tol) then
          result = list(0.0 0.0)
        else
          ; Prefer normal db move.
          ok = gfMoveFigByDelta(inst geGetEditCellView() dx dy)

          ; Fallback: update transform origin directly.
          unless(ok
            orient = gfInstOrient(inst)
            mag = gfInstMag(inst)

            ok = errset(
              inst~>transform = list(newOrigin orient mag)
              t
            )
          )

          unless(ok
            ok = errset(
              inst~>xy = newOrigin
              t
            )
          )

          if(ok then
            when(gfVerbose
              printf("goldFishToolkit: moved instance %L from %L to %L, dx=%L dy=%L\n"
                     gfInstName(inst) origin newOrigin dx dy)
            )
            result = list(dx dy)
          else
            warn("goldFishToolkit: failed to move instance to grid: %L\n" inst)
          )
        )
      else
        warn("goldFishToolkit: selected instance has no usable origin, skipped: %L\n" inst)
      )
    )

    result
  )
)


procedure(gfRecreateRectOnGrid(fig cv grid tol)
  let((oldBBox newBBox lpp newFig result)
    result = nil
    oldBBox = gfBBox(fig)

    when(oldBBox
      newBBox = list(
        gfPointToGrid(car(oldBBox) grid)
        gfPointToGrid(cadr(oldBBox) grid)
      )

      if(!gfBBoxChangedP(oldBBox newBBox tol) then
        result = list(0.0 0.0)
      else
        if((gfPtX(car(newBBox)) == gfPtX(cadr(newBBox))) ||
           (gfPtY(car(newBBox)) == gfPtY(cadr(newBBox))) then
          warn("goldFishToolkit: snapped rect would become degenerate, skipped: %L\n" fig)
        else
          lpp = gfLPP(fig)
          newFig = dbCreateRect(cv lpp newBBox)
          gfCopyProps(fig newFig)

          dbDeleteObject(fig)
          gfSelectObjectSafe(newFig)

          result = list(
            gfPtX(car(newBBox)) - gfPtX(car(oldBBox))
            gfPtY(car(newBBox)) - gfPtY(car(oldBBox))
          )
        )
      )
    )

    result
  )
)


procedure(gfRecreatePolygonOnGrid(fig cv grid tol)
  let((oldPts newPts lpp newFig result)
    result = nil
    oldPts = fig~>points

    newPts = foreach(mapcar pt oldPts
      gfPointToGrid(pt grid)
    )

    if(!gfPointListChangedP(oldPts newPts tol) then
      result = list(0.0 0.0)
    else
      lpp = gfLPP(fig)
      newFig = dbCreatePolygon(cv lpp newPts)
      gfCopyProps(fig newFig)

      dbDeleteObject(fig)
      gfSelectObjectSafe(newFig)

      result = list(0.0 0.0)
    )

    result
  )
)


procedure(gfRecreatePathOnGrid(fig cv grid tol)
  let((oldPts newPts oldWidth newWidth lpp newFig changed result)
    result = nil
    oldPts = fig~>points
    oldWidth = fig~>width

    newPts = foreach(mapcar pt oldPts
      gfPointToGrid(pt grid)
    )

    newWidth = gfRoundWidth(oldWidth grid)

    changed = gfPointListChangedP(oldPts newPts tol) ||
              (abs(oldWidth - newWidth) > tol)

    if(!changed then
      result = list(0.0 0.0)
    else
      lpp = gfLPP(fig)
      newFig = dbCreatePath(cv lpp newPts newWidth)
      gfCopyProps(fig newFig)

      dbDeleteObject(fig)
      gfSelectObjectSafe(newFig)

      result = list(0.0 0.0)
    )

    result
  )
)


procedure(gfRecreatePathSegOnGrid(fig cv grid tol)
  let((oldPts newPts oldWidth newWidth lpp newFig changed result)
    result = nil
    oldPts = list(fig~>beginPt fig~>endPt)
    oldWidth = fig~>width

    newPts = foreach(mapcar pt oldPts
      gfPointToGrid(pt grid)
    )

    newWidth = gfRoundWidth(oldWidth grid)

    changed = gfPointListChangedP(oldPts newPts tol) ||
              (abs(oldWidth - newWidth) > tol)

    if(!changed then
      result = list(0.0 0.0)
    else
      lpp = gfLPP(fig)

      ; For compatibility, recreate pathSeg as path.
      newFig = dbCreatePath(cv lpp newPts newWidth)
      gfCopyProps(fig newFig)

      dbDeleteObject(fig)
      gfSelectObjectSafe(newFig)

      result = list(0.0 0.0)
    )

    result
  )
)


procedure(gfSnapOneObjToGrid(obj cv grid)
  let((typ result)
    result = nil

    when(obj
      typ = gfObjType(obj)

      cond(
        ((equal typ "inst")
          result = gfMoveInstOriginToGrid(obj grid gfOffGridTol)
        )

        ((equal typ "rect")
          result = gfRecreateRectOnGrid(obj cv grid gfOffGridTol)
        )

        ((or (equal typ "polygon") (equal typ "boundary"))
          result = gfRecreatePolygonOnGrid(obj cv grid gfOffGridTol)
        )

        ((equal typ "path")
          result = gfRecreatePathOnGrid(obj cv grid gfOffGridTol)
        )

        ((equal typ "pathSeg")
          result = gfRecreatePathSegOnGrid(obj cv grid gfOffGridTol)
        )

        (t
          when(gfVerbose
            printf("goldFishToolkit: skip unsupported selected object during snap: %L\n" obj)
          )
        )
      )
    )

    result
  )
)


procedure(gfSnapSelectedToGrid(@optional (cv gfCurrentLayoutCV()) (grid gfSnapGrid))
  let((selSet checkedInst checkedShape skipped processed result typ)
    selSet = geGetSelSet()
    checkedInst = 0
    checkedShape = 0
    skipped = 0
    processed = 0

    unless(grid && grid > 0
      error("goldFishToolkit: invalid gfSnapGrid = %L\n" grid)
    )

    printf("goldFishToolkit: snap selected to grid. Instances move; standalone shapes resize/vertex-snap. grid=%L\n"
           grid)

    foreach(obj selSet
      typ = gfObjType(obj)

      cond(
        ((equal typ "inst")
          checkedInst = checkedInst + 1
          result = gfSnapOneObjToGrid(obj cv grid)

          when(result
            processed = processed + 1
          )
        )

        ((gfShapeAllowedP obj)
          checkedShape = checkedShape + 1
          result = gfSnapOneObjToGrid(obj cv grid)

          when(result
            processed = processed + 1
          )
        )

        (t
          skipped = skipped + 1

          when(gfVerbose
            printf("goldFishToolkit: skip selected unsupported object: %L\n" obj)
          )
        )
      )
    )

    printf("goldFishToolkit: snap finished: inst=%d, shapes=%d, processed=%d, skipped=%d\n"
           checkedInst checkedShape processed skipped)

    processed
  )
)


procedure(gfDebugSelectedObjects(@optional (grid gfSnapGrid))
  let((typ bBox width pts origin libCell)
    foreach(obj geGetSelSet()
      typ = gfObjType(obj)

      printf("\nObject %L\n" obj)
      printf("  objType = %L\n" typ)

      cond(
        ((equal typ "inst")
          origin = gfInstOrigin(obj)
          libCell = gfInstLibCell(obj)

          printf("  name      = %L\n" gfInstName(obj))
          printf("  lib/cell  = %L/%L\n" car(libCell) cadr(libCell))
          printf("  origin    = %L onGrid=%L\n"
                 origin gfPointOnGridP(origin grid gfOffGridTol))
          printf("  transform = %L\n" gfInstTransform(obj))
        )

        ((gfShapeAllowedP obj)
          printf("  lpp = %L\n" gfLPP(obj))

          bBox = gfBBox(obj)
          when(bBox
            printf("  bbox    = %L\n" bBox)
            printf("  bbox LL = %L onGrid=%L\n"
                   car(bBox) gfPointOnGridP(car(bBox) grid gfOffGridTol))
            printf("  bbox UR = %L onGrid=%L\n"
                   cadr(bBox) gfPointOnGridP(cadr(bBox) grid gfOffGridTol))
          )

          when(or(equal(typ "polygon") equal(typ "boundary") equal(typ "path"))
            pts = obj~>points
            printf("  points = %L\n" pts)
          )

          when(equal(typ "pathSeg")
            printf("  beginPt = %L onGrid=%L\n"
                   obj~>beginPt gfPointOnGridP(obj~>beginPt grid gfOffGridTol))
            printf("  endPt   = %L onGrid=%L\n"
                   obj~>endPt gfPointOnGridP(obj~>endPt grid gfOffGridTol))
          )

          when(or(equal(typ "path") equal(typ "pathSeg"))
            width = obj~>width
            printf("  width = %L onGrid=%L\n"
                   width !gfWidthOffGridP(width grid gfOffGridTol))
          )
        )

        (t
          printf("  skipped: unsupported object type for grid snap.\n")
        )
      )
    )

    t
  )
)


/***********************************************************************
 * Clear Steiners / BBox Fix
 ***********************************************************************/

procedure(gfClearSteinersBBoxFix(@optional (cv gfCurrentLayoutCV()))
  let((count steinersToDelete)
    count = 0
    steinersToDelete = nil

    ; Keep this simple and current-view based.
    foreach(st cv~>steiners
      steinersToDelete = cons(st steinersToDelete)
    )

    foreach(st steinersToDelete
      when(st
        dbDeleteObject(st)
        count = count + 1
      )
    )

    ; Some Virtuoso versions do not define dbRecomputeBBox.
    ; Use errset(... nil) to suppress harmless undefined-function messages.
    errset(dbRecomputeBBox(cv) nil)
    errset(geRefresh() nil)

    printf("goldFishToolkit: deleted %d steiners / Steiners. BBox refresh attempted.\n"
           count)

    count
  )
)


/***********************************************************************
 * Create Stair Line
 ***********************************************************************/

procedure(gfStairLineCaptureTarget()
  gfStairLineTargetWin = hiGetCurrentWindow()
  gfStairLineTargetCV  = gfCurrentLayoutCV()
  gfStairLineTargetCV
)


procedure(gfStairLineActivateTargetWindow()
  when(gfStairLineTargetWin
    errset(hiSetCurrentWindow(gfStairLineTargetWin) nil)
  )

  gfStairLineTargetWin
)


procedure(gfStairLineGetTargetCV()
  let((cv)
    cv = nil

    when(gfStairLineTargetCV && gfStairLineTargetCV~>cellViewType == "maskLayout"
      cv = gfStairLineTargetCV
    )

    unless(cv
      cv = gfCurrentLayoutCV()
    )

    cv
  )
)


procedure(gfStairLineGetLPP()
  let((val lpp r)
    val = nil
    lpp = nil

    errset(val = gfStairLineForm->LineLayerField->value nil)

    when(val
      lpp = parseString(val)
    )

    ; Try entry layer if "Use Current Entry Layer" was chosen or parsing failed.
    when((!lpp) || length(lpp) < 2 || equal(car(lpp) "Use")
      r = errset(leGetEntryLayer() nil)
      when(r && car(r)
        lpp = car(r)
      )
    )

    unless(lpp && length(lpp) >= 2
      error("goldFishToolkit: cannot determine stair line layer/purpose. Please select an explicit layer.\n")
    )

    list(car(lpp) cadr(lpp))
  )
)


procedure(gfStairLineGUI()
  let((tech LayLabelField LineLayerField LongSideField ShortSideField
       LineLengthField StepField TipsField)
    gfStairLineCaptureTarget()
    tech = techGetTechFile(gfStairLineTargetCV)

    if(!boundp('gfStairLineForm) || gfStairLineForm == nil then
      LayLabelField = hiCreateLabel(
        ?name 'LayLabelField
        ?labelText "Select Layer : "
        ?justification 'left
        ?enabled t
      )

      LineLayerField = leCreateLayerField(
        'LineLayerField
        ?prependChoices "Use Current Entry Layer"
        ?maxVisibleItems 25
        ?techFile tech
        ?syncedPaletteWindow gfStairLineTargetWin
      )

      LongSideField = hiCreateFloatField(
        ?name 'LongSideField
        ?prompt "Long Side :"
        ?value gfStairLineDefaultLongSide
        ?range '(0.0 10000.0)
      )

      ShortSideField = hiCreateFloatField(
        ?name 'ShortSideField
        ?prompt "Short Side :"
        ?value gfStairLineDefaultShortSide
        ?range '(0.0 10000.0)
      )

      LineLengthField = hiCreateFloatField(
        ?name 'LineLengthField
        ?prompt "Line Length :"
        ?value gfStairLineDefaultLineLength
        ?range '(0.0 10000.0)
      )

      StepField = hiCreateIntField(
        ?name 'StepField
        ?prompt "Step :"
        ?value gfStairLineDefaultStep
        ?range '(2 1000)
      )

      TipsField = hiCreateLabel(
        ?name 'TipsField
        ?labelText "Tips :\nShape will be created at origin, then pasted interactively."
        ?justification 'left
        ?enabled nil
      )

      gfStairLineForm = hiCreateAppForm(
        ?name 'gfStairLineForm
        ?formTitle "Create Stair Line"
        ?callback "gfCreateStairLine()"
        ?buttonLayout 'OKCancel
        ?fields list(
          list(LayLabelField    25:5   90:30  50)
          list(LineLayerField  120:5  170:30  80)
          list(LongSideField    30:40 150:30  70)
          list(ShortSideField  200:40 150:30  70)
          list(LineLengthField  30:75 150:30  70)
          list(StepField       200:75 150:30  70)
          list(TipsField        25:120 280:40 70)
        )
      )
    )

    hiDisplayForm(gfStairLineForm)
  )
)


procedure(gfCreateStairLine()
  let((cv lpp longSide shortSide lineLength stepInput stepCount
       diffH stepH stepLength currentX currentY points i aimShape)
    gfStairLineActivateTargetWindow()
    cv = gfStairLineGetTargetCV()

    unless(cv
      error("goldFishToolkit: no valid layout cellView for stair line.\n")
    )

    lpp = gfStairLineGetLPP()

    longSide   = gfStairLineForm->LongSideField->value
    shortSide  = gfStairLineForm->ShortSideField->value
    lineLength = gfStairLineForm->LineLengthField->value
    stepInput  = gfStairLineForm->StepField->value

    stepCount = stepInput - 1
    when(stepCount < 1
      stepCount = 1
    )

    points = list(gfMakePt(0 0))
    points = append1(points gfMakePt(0 longSide))

    diffH = float(longSide - shortSide)
    stepH = round(diffH / stepCount * 100.0) / 100.0
    stepLength = (lineLength - stepH * stepCount) / (stepCount + 1)
    stepLength = round(stepLength * 100.0) / 100.0

    currentX = 0.0
    currentY = longSide

    for(i 1 stepCount
      currentX = currentX + stepLength
      points = append1(points gfMakePt(currentX currentY))

      currentX = currentX + stepH
      currentY = currentY - stepH
      points = append1(points gfMakePt(currentX currentY))
    )

    currentX = lineLength
    points = append1(points gfMakePt(currentX currentY))
    points = append1(points gfMakePt(currentX 0))

    gfDeselectAll()

    aimShape = dbCreatePolygon(cv lpp points)

    unless(aimShape
      error("goldFishToolkit: failed to create stair line polygon.\n")
    )

    gfSelectObjectSafe(aimShape)

    when(gfStairLinePlaceByPaste
      ; Interactive placement by yank/delete/paste.
      ; Cancel any stale enter function first to avoid leFinishWire context warnings.
      errset(geCancelEnterFun() nil)
      errset(leHiYank() t)
      errset(leHiDelete() t)
      errset(leHiPaste() t)
    )

    printf("goldFishToolkit: stair line created. long=%L short=%L length=%L steps=%L layer=%L\n"
           longSide shortSide lineLength stepInput lpp)

    aimShape
  )
)


; Backward-compatible aliases for the user's older script.
procedure(StairLineGUI()
  gfStairLineGUI()
)


procedure(CreateStairLine()
  gfCreateStairLine()
)


/***********************************************************************
 * Menu Callbacks
 ***********************************************************************/

procedure(gfCBRefillSelected()
  errset(gfRefillSelectedPins() t)
)


procedure(gfCBRefillAll()
  errset(gfRefillAllPins() t)
)


procedure(gfCBDeleteRefill()
  errset(gfDeleteRefillPins() t)
)


procedure(gfCBSelectOffGrid()
  errset(gfSelectOffGridObjects() t)
)


procedure(gfCBSnapSelected()
  errset(gfSnapSelectedToGrid() t)
)


procedure(gfCBClearSteiners()
  errset(gfClearSteinersBBoxFix() t)
)


procedure(gfCBStairLine()
  errset(gfStairLineGUI() t)
)


procedure(gfCBPrintSettings()
  gfPrintSettings()
)


/***********************************************************************
 * Menu Creation
 ***********************************************************************/

procedure(gfCreateMenu()
  let((itemRefillSel itemRefillAll itemRefillDel
       itemSelectOffGrid itemSnap itemClear itemStair itemSettings
       menuRefill menuUtils sliderRefill sliderUtils mainMenu)

    itemRefillSel = hiCreateMenuItem(
      ?name 'gfMenuItemRefillSelected
      ?itemText "Refill Selected Hierarchy Pins"
      ?callback "gfCBRefillSelected()"
    )

    itemRefillAll = hiCreateMenuItem(
      ?name 'gfMenuItemRefillAll
      ?itemText "Refill All Hierarchy Pins"
      ?callback "gfCBRefillAll()"
    )

    itemRefillDel = hiCreateMenuItem(
      ?name 'gfMenuItemDeleteRefill
      ?itemText "Delete Generated Refill Shapes"
      ?callback "gfCBDeleteRefill()"
    )

    menuRefill = hiCreatePulldownMenu(
      'gfMenuHierPinRefill
      "Hierarchical Pin Refill"
      list(itemRefillSel itemRefillAll itemRefillDel)
    )

    sliderRefill = hiCreateSliderMenuItem(
      ?name 'gfMenuSliderHierPinRefill
      ?itemText "Hierarchical Pin Refill"
      ?subMenu menuRefill
    )

    itemSelectOffGrid = hiCreateMenuItem(
      ?name 'gfMenuItemSelectOffGrid
      ?itemText "Select Off-Grid Objects"
      ?callback "gfCBSelectOffGrid()"
    )

    itemStair = hiCreateMenuItem(
      ?name 'gfMenuItemCreateStairLine
      ?itemText "Create Stair Line"
      ?callback "gfCBStairLine()"
    )

    itemSnap = hiCreateMenuItem(
      ?name 'gfMenuItemSnapSelected
      ?itemText "Snap Selected to Grid"
      ?callback "gfCBSnapSelected()"
    )

    itemClear = hiCreateMenuItem(
      ?name 'gfMenuItemClearSteiners
      ?itemText "Clear Steiners / BBox Fix"
      ?callback "gfCBClearSteiners()"
    )

    menuUtils = hiCreatePulldownMenu(
      'gfMenuLayoutUtils
      "Layout Utilities"
      list(itemSelectOffGrid itemStair itemSnap itemClear)
    )

    sliderUtils = hiCreateSliderMenuItem(
      ?name 'gfMenuSliderLayoutUtils
      ?itemText "Layout Utilities"
      ?subMenu menuUtils
    )

    itemSettings = hiCreateMenuItem(
      ?name 'gfMenuItemPrintSettings
      ?itemText "Print Settings"
      ?callback "gfCBPrintSettings()"
    )

    mainMenu = hiCreatePulldownMenu(
      'goldFishToolkitMenu
      "goldFishToolkit"
      list(sliderRefill sliderUtils itemStair itemSettings)
    )

    mainMenu
  )
)


procedure(gfInstallMenu(@optional (win hiGetCurrentWindow()))
  let((menu ok result)
    result = nil

    if(win then
      errset(hiDeleteBannerMenu(win 'goldFishToolkitMenu) nil)

      menu = gfCreateMenu()

      ok = errset(
        hiInsertBannerMenu(win menu gfMenuPosition)
        t
      )

      if(ok then
        printf("goldFishToolkit: menu installed. Check menu bar: goldFishToolkit\n")
        result = t
      else
        warn("goldFishToolkit: menu installation failed. You can still run commands manually.\n")
      )
    else
      warn("goldFishToolkit: no current window. Open a layout window and run gfInstallMenu().\n")
    )

    result
  )
)


procedure(gfReinstallMenu(@optional (win hiGetCurrentWindow()))
  gfInstallMenu(win)
)


/***********************************************************************
 * Menu Triggers / Debug
 ***********************************************************************/

gfLayoutAppTypes = '(
  "maskLayout"
  "maskLayoutXL"
  "maskLayoutEXL"
  "maskLayoutMXL"
  "pideLayout"
  "explorer-maskLayout"
  "maestro-maskLayout"
  "adexl-maskLayout"
  "adegxl-maskLayout"
  "analogArtist-maskLayout"
)


procedure(gfMenuTrigger(@optional (args nil))
  list(gfCreateMenu())
)


procedure(gfPostInstallMenu(@optional (args nil))
  let((win ok)
    win = hiGetCurrentWindow()

    when(gfVerbose
      printf("goldFishToolkit: gfPostInstallMenu called, win=%L\n" win)
    )

    when(win
      ok = errset(gfInstallMenu(win) t)

      unless(ok
        warn("goldFishToolkit: post-install gfInstallMenu failed.\n")
      )
    )

    t
  )
)


procedure(gfRegisterMenuTriggers()
  let((app ok)
    foreach(app gfLayoutAppTypes
      ok = errset(
        deRegUserTriggers(app nil 'gfMenuTrigger nil)
        t
      )

      if(ok then
        printf("goldFishToolkit: user menu trigger registered for %s\n" app)
      else
        warn("goldFishToolkit: failed to register user menu trigger for %s\n" app)
      )

      ok = errset(
        deRegUserTriggers(app nil nil 'gfPostInstallMenu)
        t
      )

      if(ok then
        printf("goldFishToolkit: post-install trigger registered for %s\n" app)
      else
        warn("goldFishToolkit: failed to register post-install trigger for %s\n" app)
      )
    )

    ; If current window is already layout, install once immediately.
    errset(gfInstallMenu(hiGetCurrentWindow()) t)

    t
  )
)


procedure(gfPlistGet(pl key)
  let((tail)
    tail = member(key pl)

    if(tail then
      cadr(tail)
    else
      nil
    )
  )
)


procedure(gfNormalizeAppInfo(raw)
  ; deGetAppInfo may return:
  ;   (nil key val key val ...)
  ; or
  ;   ((nil key val key val ...))
  while(listp(raw) && listp(car(raw)) && car(raw)
    raw = car(raw)
  )

  raw
)


procedure(gfCheckOneMenuTrigger(app)
  let((res raw pl)
    res = errset(deGetAppInfo(app) nil)

    if(res then
      raw = car(res)
      pl = gfNormalizeAppInfo(raw)

      printf("\n========== %s ==========\n" app)
      printf("raw deGetAppInfo = %L\n" raw)
      printf("userMenuTrigList         = %L\n" gfPlistGet(pl 'userMenuTrigList))
      printf("userPostInstallTrigList  = %L\n" gfPlistGet(pl 'userPostInstallTrigList))
      printf("_userMenuTrigList        = %L\n" gfPlistGet(pl '_userMenuTrigList))
      printf("_userPostInstallTrigList = %L\n" gfPlistGet(pl '_userPostInstallTrigList))
    else
      warn("goldFishToolkit: deGetAppInfo failed for %s\n" app)
    )

    t
  )
)


procedure(gfCheckMenuTrigger()
  foreach(app gfLayoutAppTypes
    gfCheckOneMenuTrigger(app)
  )

  t
)


procedure(gfInstallBindKeys()
  when(gfInstallStairLineBindKey
    errset(
      hiSetBindKey("Layout" gfStairLineBindKey "gfStairLineGUI()")
      t
    )

    printf("goldFishToolkit: bindkey installed: Layout %s -> gfStairLineGUI()\n"
           gfStairLineBindKey)
  )

  t
)


/***********************************************************************
 * Auto Load
 ***********************************************************************/

printf("Loading goldFishToolkit clean full version...\n")

gfRegisterMenuTriggers()
gfInstallBindKeys()

printf("goldFishToolkit loaded.\n")
printf("Menu should appear automatically in newly opened layout windows.\n")
printf("If current layout was already open before loading, close/reopen it, or run:\n")
printf("  gfInstallMenu()\n")
printf("Useful manual commands:\n")
printf("  gfRefillAllPins()\n")
printf("  gfRefillSelectedPins()\n")
printf("  gfDeleteRefillPins()\n")
printf("  gfSelectOffGridObjects()\n")
printf("  gfSnapSelectedToGrid()\n")
printf("  gfClearSteinersBBoxFix()\n")
printf("  gfStairLineGUI()\n")
printf("  gfDebugSelectedObjects()\n")
printf("\n")
