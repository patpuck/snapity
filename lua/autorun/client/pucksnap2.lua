if !CLIENT then return end

local PS = "pucksnap2"
local PS_ = PS.."_"

local colors_fgcgray = Color(180, 180, 180) -- fgc gray
local colors_fgcorange = Color(255, 131, 0) -- fgc orange

local _h,_s,_v = ColorToHSV(colors_fgcgray)
local HSVcolors_fgcgray = { h = _h, s = _s, v = _v }
local _h,_s,_v = ColorToHSV(colors_fgcorange)
local HSVcolors_fgcorange = { h = _h, s = _s, v = _v }

local DIST_EPSILON = 0.031234741210938
local sizeLimit = 128 -- valves hardcoded axial size limit on AABB for +use pickup on physobj :>

local ENABLED = false
local ISTOOLGUN = false
local CANLOCK = false
local CELLWIDTH

local condefs = {
    enable                 = true,
    drawfaceindeces        = false,
    drawhitnormals         = false,
    drawfaces              = true,
    drawfacesignorez       = true,
    drawiconboneindex      = true,
    drawiconmasscenter     = false,
    drawpseudonormals      = false,
    drawvertexindeces      = false,
    drawfullconvex         = false,
    faceculling            = true,
    facesmoothing          = 0.9,
    dropshadowlength       = 3*DIST_EPSILON,
    dropshadowopacity      = 0.8,
    lineopacity            = 0.75,
    lineignorez            = false,
    masscenterproj         = false,
    handlepickup           = true,
    anyweapon              = false,
    toolgunuseonly         = true,
    drawworldspaceaabb     = true,
    fponlywhenlockable     = true,
    fpsforgridyield        = 3000,
    drawgridwithouttoolgun = false,
    drawlineshadows        = true,
    cellwidth              = 2,
    propaccomodations      = true,
    zoomscroll             = true,
    minzoom                = 1,
    maxzoom                = 0,
    deltazoom              = 1
}

local focalicons = {
    edge            = {default = "cog",             selected = "add"},
    masscenteroff   = {default = "lorry_flatbed",   selected = "lorry_delete"},
    masscenter      = {default = "lorry",           selected = "lorry_add"},
    tick            = {default = "bullet_star",     selected = "bullet_add"},
    rayend          = {default = "disconnect",     selected = "connect"}
}

local propaccomodations = {
    hunter = { length = 11.8625 },
    squad  = { length = 12 }
}

-- print(focalicons.edge.selected)

local convars = {}

for key, value in pairs(condefs) do

    if type(value) == "table" then value = value[1] end

    if type(value) == "boolean" then
        if value then value = 1 else value = 0 end
    end

    convars[key] = CreateClientConVar(PS_..key, value, true, false)

end

for key, tab in pairs(focalicons) do

    for state, value in pairs(tab) do

        local cvar = CreateClientConVar(PS_.."focalicons_"..state.."_"..key, value, true, false)
        cvar:SetString( value )

    end

end

for groupname, group in pairs(propaccomodations) do

    for k, v in pairs(group) do

        CreateClientConVar(PS_.."propaccomodations_"..groupname.."_"..k, v, true, false)

    end

end

local function cBool(cvarsuffix)
    return GetConVar(PS_..cvarsuffix):GetBool()
end

local function cStr(cvarsuffix)
    return GetConVar(PS_..cvarsuffix):GetString()
end

local function cIcon(type, state)
    state = state or "default"
    return cStr("focalicons_"..state.."_"..type)
end

local function cNum(cvarsuffix)
    return GetConVar(PS_..cvarsuffix):GetFloat()
end

hook.Remove( "PopulateToolMenu", "CustomMenuSettings")
hook.Add( "PopulateToolMenu", PS_.."customMenu", function()
    spawnmenu.AddToolMenuOption("Options", "Player", PS_.."settings", PS, "", "", function(panel)

        panel:Help("Creates a helper snap-grid over the physical mesh of the target entity.")

        panel:ToolPresets( PS, condefs )

        panel:CheckBox( "Enable", PS_.."enable" )

    end)
end)

local FocusEntity = {}

local PSID_Timeouts = {}
local timeout = 3

local function FocusConvex()

    return FocusEntity.FocusConvex or FocusEntity.FocusConvexPREV or 1

end

local function boxVertsLocal(m, M)

    local V = {
        xyz = Vector( m.x, m.y, m.z ),
        Xyz = Vector( M.x, m.y, m.z ),
        xYz = Vector( m.x, M.y, m.z ),
        XYz = Vector( M.x, M.y, m.z ),
        xyZ = Vector( m.x, m.y, M.z ),
        XyZ = Vector( M.x, m.y, M.z ),
        xYZ = Vector( m.x, M.y, M.z ),
        XYZ = Vector( M.x, M.y, M.z )
    }
    
    return V

end

function FocusEntity.SetPhysicalData()

    local ent = FocusEntity.Entity

    FocusEntity.PropOffsetMatrix    = Matrix() -- doesnt apply to ragdolls i think (please report if u find a counterexample)  
    FocusEntity.PropOffsetMatrixInv = Matrix()
    FocusEntity.MeshConvexes        = {}
    FocusEntity.MassCenters         = {}
    FocusEntity.PhysicalAABBs       = {}
    FocusEntity.PhysicalAABBsVerts  = {}
    FocusEntity.PhysicalAABBsSize   = {}
    FocusEntity.BoneMatrices        = {}
    FocusEntity.CannotPickUp        = false
    FocusEntity.PhysicalWorldAABBs      = {}
    FocusEntity.PhysicalWorldAABBsSize  = {}
    FocusEntity.PhysicalWorldAABBsVerts = {}

    local temporaryEnt

    FocusEntity.PhysBoneCount = 1

    -- local isragdoll = ent:IsRagdoll() or ent:IsNPC()

    -- if ent:IsWorld() then FocusEntity.OffsetDetermined = true end
    if isragdoll or ent:IsWorld() then FocusEntity.OffsetDetermined = true end

    if ent:IsNPC() then

        print("npc")

    elseif ent:IsRagdoll() then

        print("ragdoll")

        temporaryEnt = ClientsideRagdoll( ent:GetModel() )

        -- temporaryEnt:SetNoDraw( false )

        FocusEntity.PhysBoneCount = temporaryEnt:GetPhysicsObjectCount()

        for i = 1, FocusEntity.PhysBoneCount do

            local physobj = temporaryEnt:GetPhysicsObjectNum(i-1)

            FocusEntity.MeshConvexes[i]         = physobj:GetMeshConvexes()
            FocusEntity.MassCenters[i]          = physobj:GetMassCenter()
            FocusEntity.PhysicalAABBs[i]        = {physobj:GetAABB()}
            FocusEntity.PhysicalAABBs[i][1]     = FocusEntity.PhysicalAABBs[i][1] or Vector()
            FocusEntity.PhysicalAABBsVerts[i]   = boxVertsLocal( unpack(FocusEntity.PhysicalAABBs[i]) )
            FocusEntity.PhysicalAABBsSize[i]    = FocusEntity.PhysicalAABBs[i][2] - FocusEntity.PhysicalAABBs[i][1]

        end

        FocusEntity.CannotPickUp = true
        FocusEntity.OffsetDetermined = true

        temporaryEnt:Remove()

    elseif ent:IsWorld() then

        print("world")

        FocusEntity.CannotPickUp = true
        FocusEntity.OffsetDetermined = true

    else

        print("prop")

        if !IsValid(ent) then return end -- commentcommentcommentcommentcommentcomment

        temporaryEnt = ents.CreateClientProp( ent:GetModel() )

        local physobj = temporaryEnt:GetPhysicsObject()

        if !IsValid(physobj) then print("invalid physobj") temporaryEnt:Remove() return end
        -- ragdoll:DrawShadow( true )

        local rI, rF = temporaryEnt:GetPos(), ent:GetPos()

        temporaryEnt:SetRenderMode(2)
        temporaryEnt:SetColor(Color(0,0,0,0))
        temporaryEnt:DrawShadow( false )

        temporaryEnt:SetPos(rF)

        temporaryEnt:GetPhysicsObjectNum(0):EnableMotion(false)

        FocusEntity.MeshConvexes            = {physobj:GetMeshConvexes()}
        FocusEntity.MassCenters             = {physobj:GetMassCenter()}
        FocusEntity.PhysicalAABBs           = {{physobj:GetAABB()}}
        FocusEntity.PhysicalAABBs[1][1]     = FocusEntity.PhysicalAABBs[1][1] or Vector()
        FocusEntity.PhysicalAABBsVerts[1]   = boxVertsLocal( unpack(FocusEntity.PhysicalAABBs[1]) )
        FocusEntity.PhysicalAABBsSize[1]    = FocusEntity.PhysicalAABBs[1][2] - FocusEntity.PhysicalAABBs[1][1]

        local size = FocusEntity.PhysicalAABBs[1][2] - FocusEntity.PhysicalAABBs[1][1]
        
        if size.x > sizeLimit or size.y > sizeLimit or size.z > sizeLimit then
            FocusEntity.CannotPickUp = true
        end

        local id = math.floor(CurTime()*1000)

        hook.Remove( "Think", PS_.."tempent_offsetmatrix_wrapup"..id )

        local timeoutstart = CurTime()

        hook.Add("Think", PS_.."tempent_offsetmatrix_wrapup"..id, function()

            if !IsValid(temporaryEnt) 
                or !IsValid(ent) 
                or ent:GetPos():LengthSqr() < 0.1 
                or ( CurTime() > timeoutstart + timeout )
            then 
                hook.Remove( "Think", PS_.."tempent_offsetmatrix_wrapup"..id ) 
                if FocusEntity then
                    FocusEntity.OffsetDetermined = true
                end
                return 
            else 
                temporaryEnt:SetPos(rF) 
            end

            temporaryEnt:SetPos(rF)

            local mat   = temporaryEnt:GetBoneMatrix(0) or Matrix()

            local tran  = mat:GetTranslation()

            -- print("TRAN:", tran)

            -- print("NOT FRIENDLY!!!",CurTime(),tran, tran:LengthSqr() < 1, (ent:GetPos():LengthSqr() < 1))
            -- print(temporaryEnt:GetPos())

            if tran:LengthSqr() < 1 or (ent:GetPos():LengthSqr() < 1) then return end -- wait for the position to be truly set

            FocusEntity.PropOffsetMatrix = mat
            FocusEntity.PropOffsetMatrix:SetTranslation( tran - (rF - rI) )
            FocusEntity.PropOffsetMatrixInv = mat:GetInverseTR()

            -- print("=========== PROP OFFSET MATRIX ============================================")
            -- print(FocusEntity.PropOffsetMatrix)
            -- print(FocusEntity.PropOffsetMatrixInv)

            FocusEntity.OffsetDetermined = true

            temporaryEnt:Remove()
            temporaryEnt = nil

        end)

    end

end

local EPSILON_THETA = 0.3 -- raw shit i pulled out of my ass (degrees)
-- local EPSILON_THETA = 0.1
-- local EPSILON_THETA = 10

local function keyForNorm(v) -- naming the verts i culled like little sheep
    local eps_theta = math.rad( EPSILON_THETA )
    local eps = 2 * math.sin(eps_theta * 0.5)
    return string.format("%d:%d:%d",
        math.floor(v.x / eps + 0.5),
        math.floor(v.y / eps + 0.5),
        math.floor(v.z / eps + 0.5))
end

local function keyForPos(v)
    local eps = 0.1
    return string.format("%d:%d:%d",
        math.floor(v.x / eps + 0.5),
        math.floor(v.y / eps + 0.5),
        math.floor(v.z / eps + 0.5))
end

local function keyForDist(r)
    -- local eps = 4 -- quarter inch sensitivity before 2 distances are considered equal
    local eps = 0.25
    return string.format("%d", math.floor(r / eps + 0.5))
end

local function keyForEdge(A,B) return keyForPos(A).."|"..keyForPos(B) end

local function Solve3x3(r1, r2, r3, b) -- r1,r2,r3 = rows of M (Vectors), symmetric M
    local detM = r1:Dot( r2:Cross(r3) )
    if math.abs(detM) < 1e-8 then return nil end -- rank-deficient, fall back
    local x = b:Dot ( r2:Cross(r3) ) / detM
    local y = r1:Dot( b:Cross(r3) ) / detM
    local z = r1:Dot( r2:Cross(b) ) / detM
    return Vector(x, y, z)
end

local function VertexOffset(uniqueNormals, d)

    if #uniqueNormals == 1 then
        return uniqueNormals[1]
    elseif #uniqueNormals == 2 then
        local n1, n2 = uniqueNormals[1], uniqueNormals[2]
        local bis = (n1 + n2) -- bisekkktor
        local len = bis:Length()
        if len < 1e-6 then return n1 end -- n1 = -n2, shouldn't happen on a convex hull
        bis = bis / len
        return bis:Dot(n1) * bis
    end

    local r1, r2, r3, b = Vector(), Vector(), Vector(), Vector()
    for _, n in ipairs(uniqueNormals) do
        r1 = r1 + n.x * n
        r2 = r2 + n.y * n
        r3 = r3 + n.z * n
        b  = b  + n
    end

    return Solve3x3(r1, r2, r3, b) or uniqueNormals[1] -- fallback if still singular

end

-- print(VertexOffset({
--     Vector(0,0,1),
--     Vector(0,1,0)
-- }))

-- local function keypress(player, key)
--     if (key == IN_USE and GetConVarNumber("snap_disableuse") == 0) then
--         puckpress()
--     end
-- end


local function peepeeNoPress()
    FocusEntity.Locked = false
end

ALTING = false

local function initialstuff()

    -- local snd = CreateSound(LocalPlayer(), "ui/hint.wav")
    -- local sndqty = 3
    -- local snd = {}
    -- for i = 1, sndqty do 
    --     snd[i] = CreateSound(LocalPlayer(), "physics/metal/chain_impact_soft"..i..".wav")
    -- end

    -- local sndBqty = 2
    -- local sndB = {}
    -- for i = 1, sndBqty do 
    --     sndB[i] = CreateSound(LocalPlayer(), "physics/metal/chain_impact_hard"..i..".wav")
    -- end

    -- local sndgrabhard = CreateSound(LocalPlayer(), "physics/metal/chain_impact_hard2.wav")
    -- local sndgrabsoft = CreateSound(LocalPlayer(), "physics/metal/chain_impact_soft1.wav")
    local sndgrabhard = CreateSound(LocalPlayer(), "weapons/clipempty_pistol.wav")
    local sndgrabsoft = CreateSound(LocalPlayer(), "weapons/clipempty_rifle.wav")

    local function peepeePress()

        if !ISLOCKABLE then return end

        local fp = FocusEntity.Grid.focalpoint

        if fp == nil then return end

        local ty = fp.type
        local pitch = 50
        local sou = sndgrabhard
        if ty == "masscenter" or ty == "centroid" then
            pitch = 30
            sou = sndgrabsoft
        end

        FocusEntity.Locked = true
        FocusEntity.LockedTimestamp = CurTime()
        sou:Stop()
        sou:PlayEx(1, pitch)
        -- sou:ChangePitch(0, 0.3)

    end

    -- hook.Add("PlayerBindPress", PS_.."HandlePickup", function(ply, bind, pressed, code) -- fuck ts

    --     -- return true 
    --     -- print(bind)
    --     if !ENABLED then return end
    --     -- if !cBool("handlepickup") then return end
    --     if input.LookupBinding("+"..PS_.."snap") != nil then -- E if theres nothn else
    --         if bind == "+use" then return end
    --     else
    --         -- print("ADFKJSJKDSA222")
    --         if bind != "+use" then return end
    --     end
    --     -- if FocusEntity.CannotPickUp then return end
    --     local ent = FocusEntity.Entity
    --     if !IsValid(ent) then return end
    --     -- print(code)
    --     input.LookupBinding( "+"..PS_.."snap" )

    --     print(FocusEntity.Entity:GetFlags())

    --     if FocusEntity.Locked then
    --         peepeeNoPress()
    --     else
    --         peepeePress()
    --     end

    --     -- return true

    -- end)

    concommand.Add("+"..PS_.."snap", function() peepeePress()   end)
    concommand.Add("-"..PS_.."snap", function() peepeeNoPress() end)


    hook.Remove("KeyPress", PS_.."press")
    hook.Add("KeyPress", PS_.."press", function(ply, key)

        if !ENABLED then return end
        if input.LookupBinding("+"..PS_.."snap") != nil then return end
        if (key == IN_USE) then peepeePress() end
        if (key == IN_WALK) then ALTING = true end

    end)

    hook.Remove("KeyRelease", PS_.."release")
    hook.Add("KeyRelease", PS_.."release", function(ply, key)

        if !ENABLED then return end
        if input.LookupBinding("+"..PS_.."snap") != nil then return end
        if (key == IN_USE) then peepeeNoPress() end
        if (key == IN_WALK) then ALTING = false end

    end)

    local function peepeeSetZoom(zoom)
        convars.cellwidth:SetFloat(zoom)
    end

    local function peepeeZoom(dw)
        dw = dw or 1

        -- local k0 = FocusEntity.Grid.focalpoint.pos
        -- FocusEntity.Grid.focalpoint.pos = k0 + (k0-FocusEntity.GridCenter) * dw

        peepeeSetZoom(CELLWIDTH + dw)
    end

    concommand.Add(PS_.."zoomout", function() peepeeZoom(-1) end)
    concommand.Add(PS_.."zoomin",  function() peepeeZoom()   end)

    hook.Remove("CreateMove", PS_.."scroll")
    hook.Add("CreateMove", PS_.."scroll", function(cmd)

        if !ENABLED then return end
        if !FocusEntity.Locked then return end

        local wheel = cmd:GetMouseWheel()
        if wheel ~= 0 then

            local dz = cNum("deltazoom")

            local dw = wheel * dz

            if CELLWIDTH+dw < dz then 
                peepeeSetZoom(dz)
                return
            end

            peepeeZoom(dw)

        end
    end)


    hook.Remove("KeyPress", PS_.."press")
    hook.Add("KeyPress", PS_.."press", function(ply, key)

        if !ENABLED then return end
        if input.LookupBinding("+"..PS_.."snap") != nil then return end
        if (key == IN_USE) then peepeePress() end
        if (key == IN_WALK) then ALTING = true end

    end)

end

if IsValid( LocalPlayer() ) then
    initialstuff()
else
    hook.Add( "InitPostEntity", "some_unique_name", initialstuff )
end
-- timer.Simple(3, function() 
--     hook.Call("InitPostEntity")
-- end)

local function arrow( pos, dir, length, color, width, reverse )

    color   = color or color_white
    length  = length or 10
    dir     = dir or pos:GetNormalized()
    pos     = pos or Vector()
    reverse = reverse or false

    local eye = EyeVector()

    width = width or math.Clamp(length*0.05, 0,1)

    local tip = pos + length*dir
    local cross = eye:Cross(dir):GetNormalized()
    local kite_left  
    local kite_right 
    if !reverse then
        kite_left  = tip +  cross * width - dir * width * math.sqrt(3)
        kite_right = tip + - cross * width - dir * width * math.sqrt(3)
    else
        kite_left  = pos + cross * width + dir * width * math.sqrt(3)
        kite_right = pos - cross * width + dir * width * math.sqrt(3)
    end

    render.DrawLine( pos, tip, color)
    render.DrawLine( reverse and pos or tip, kite_left, color)
    render.DrawLine( reverse and pos or tip, kite_right, color)

end

local function arrowAB( A, B, margA, margB, color, width, reverse )

    local len = (B-A):Length()
    local norm = (B-A)/len
    margA, margB = margA or 0, margB or 0
    if len < (margA+margB) then return end

    arrow( A + norm*margA, (B-A)/len, len-(margA+margB), color, width, reverse )

end

local function Sequentialize( tab ) -- turn k, v into _, v sequential

    local out = {}

    for _, v in pairs(tab) do 

        out[ #out + 1 ] = v

    end

    return out

end

function FocusEntity.SetShapeData()

    FocusEntity.PerBone = {}

    for bone_ind, MeshConvexes in pairs(FocusEntity.MeshConvexes) do

        FocusEntity.PerBone[bone_ind] = {}
        local B = FocusEntity.PerBone[bone_ind]

        B.NormAndDForConvex = {}

        B.ConvexCount = #MeshConvexes

        B.PerConvex = {}

        B.vertices = {}
        local CVERTS = B.vertices

        for convex_ind, convex in pairs(MeshConvexes) do

            B.PerConvex[convex_ind] = {}
            local C = B.PerConvex[convex_ind]

            C.polygons = {}
            local POLS = C.polygons

            C.triangles = {}
            local TRIS = C.triangles -- FocusEntity.PerBone[bone_ind].PerConvex[convex_ind].triangles[ T ]

            C.normals = {}
            local NORS = C.normals -- FocusEntity.PerBone[bone_ind].PerConvex[convex_ind].normals[ k_detN ]

            C.vertices = {}
            local VERS = C.vertices -- FocusEntity.PerBone[bone_ind].PerConvex[convex_ind].vertices[ k_pos ]

            C.edges = {}
            local EDGS = C.edges -- FocusEntity.PerBone[bone_ind].PerConvex[convex_ind].edges[ k_pos2:k_pos1 ]

            for v, vertex in pairs(convex) do

                if (v-1)%3 != 0 then continue end

                local tri = (v+2)/3

                TRIS[tri] = {}

                local T = TRIS[tri]

                -- T.p1 = convex[ v ].pos
                -- T.p2 = convex[v+1].pos
                -- T.p3 = convex[v+2].pos

                local V

                for i = 1, 3 do

                    local pos = convex[ v+i-1 ].pos

                    T["p"..i] = pos

                end

                -- print("RAFATISU!!!!!!!") 

                T.cen   = ( T.p1 + T.p2 + T.p3 ) / 3 -- centroid

                T.det   = ( T.p3 - T.p2 ):Cross( T.p2 - T.p1 ) -- len = 2*area 

                T.detN  = T.det:GetNormalized() -- tri normal

                T.matL = Matrix()
                T.matL:SetTranslation( T.cen )
                T.matL:SetAngles( T.detN:Angle() ) -- up is already local up

                T.orgD  = T.cen:Dot(T.detN) -- distance from cen to prop origin

                local k_detN, k_orgD = keyForNorm(T.detN), keyForDist(T.orgD)

                for _, pos in pairs({T.p1, T.p2, T.p3}) do
                    
                    local k_pos = keyForPos( pos )

                    local V

                    if type(VERS[ k_pos ]) != "table" then 
                        VERS[ k_pos ] = {} 
                        V = VERS[ k_pos ]
                        V.pos = pos
                        V.uniqueNormals = {}
                    else
                        V = VERS[ k_pos ]
                    end

                    V.uniqueNormals[ k_detN ] = T.detN

                end

                if not NORS[ k_detN ] then
                    NORS[ k_detN ] = {}
                end

                local N = NORS[ k_detN ]
                table.insert(N, #N+1, tri) -- all triangles in this normal for this convex

                if B.ConvexCount == 1 then continue end -- dont do this convex seeker stuff if theres just 1 :>
                -- print("i'm multiconvex")

                local blah = k_detN.."|"..k_orgD

                -- print(blah, T.cen, T.orgD)

                if not B.NormAndDForConvex[ blah ] then 
                    B.NormAndDForConvex[ blah ] = {}
                end

                local ND = B.NormAndDForConvex[ blah ]
                -- table.insert(ND, #ND+1, convex_ind) -- all convexes who share this coplane
                if not ND[convex_ind] then
                    ND[convex_ind] = {}
                end

                local NDC = ND[convex_ind]

                table.insert(NDC, #NDC+1, tri)
                -- print("meshdist:",T.orgD,keyForDist(T.orgD))

            end

            -- for k_detN, associatedTRIS in pairs(NORS) do

            --     POLS[k_detN] = 

            -- end

            for k_pos, vert in pairs(VERS) do

                vert.pseudoNormal = VertexOffset( vert.uniqueNormals )

            end 

            FocusEntity.WindPolygons( NORS, bone_ind, convex_ind )

            for k_detN, poly in pairs(POLS) do

                local numv = #poly.vertices

                for i = 1, numv do

                    v1, v2 = poly.vertices3D[i], poly.vertices3D[i%numv+1]

                    if type(EDGS[ keyForEdge(v2,v1) ]) == "table" then

                        EDGS[ keyForEdge(v2,v1) ].normals[k_detN] = true

                    else

                        EDGS[ keyForEdge(v1,v2) ] = { v1 = v1, v2 = v2, normals = {} }
                        EDGS[ keyForEdge(v1,v2) ].normals[k_detN] = true

                    end

                end

            end

            -- print("CONVEX IND:",convex_ind)
            -- PrintTable(EDGS)

        end

        for convex_ind, C in pairs(B.PerConvex) do

            local VERS = C.vertices

            for k_pos, vert in pairs(VERS) do

                local CV

                if type( CVERTS[ k_pos ] ) != "table" then 
                    CVERTS[k_pos] = {}
                    CV = CVERTS[k_pos]
                    CV.pos = vert.pos
                    CV.uniqueNormals = {}
                else
                    CV = CVERTS[k_pos]
                end

                table.Merge( CV.uniqueNormals , vert.uniqueNormals )

            end

        end

        for k_pos, vert in pairs(CVERTS) do

            vert.pseudoNormal = VertexOffset( Sequentialize(vert.uniqueNormals) )

        end

        -- PrintTable(CVERTS)

        -- for k_pos, CV in pairs(CVERTS) do

        --     CV.normal = CV.sumNormals:GetNormalized()

        -- end

        -- local str = ""
        -- local ct = 0
        -- print("gump")
        -- for k, v in pairs(B.NormAndDForConvex) do
        --     str = str..k.."   "
        --     ct = ct+1
        --     if ct > 200 then
        --         print(str)
        --         str = ""
        --         ct = 0
        --     end
        -- end

    end

    FocusEntity.ShapeDataCompiled = true

end

local function PointProjection( matL, v )

    local r = v - matL:GetTranslation()

    local point = {
        x = r:Dot( matL:GetRight() ) ,
        y = r:Dot(   -matL:GetUp() ) -- y goes down in surface painting :<
    }

    return point

end

local function PolyProjection( matL, verts )

    local polygon = {}

    for k, v in pairs(verts) do

        polygon[k] = PointProjection( matL, v )

    end

    return polygon

end

local function WindPolygon3D(TRIS, physicsbone, convex)

    local B = FocusEntity.PerBone[physicsbone]

    local C = B.PerConvex[convex]

    local T1 = C.triangles[ TRIS[1] ]

    local edges = {}
    local edgesAtoB = {}

    local averageTranslation = Vector()
    local totalArea          = 0
    local totalMassDisp      = Vector()

    for k, tri in pairs(TRIS) do

        local T = C.triangles[ tri ]

        -- averageTranslation  = averageTranslation + T.matL:GetTranslation()
        local area2 = T.det:Dot(T.detN)
        totalArea           = totalArea + area2
        totalMassDisp       = totalMassDisp + area2*T.matL:GetTranslation()

        for edge, pair in pairs({{T.p1,T.p2},{T.p2,T.p3},{T.p3,T.p1}}) do

            local A,B = pair[1],pair[2]

            if type(edges[ keyForEdge(B,A) ]) == "table" then -- if the adverse exists then kill us both
                edges[ keyForEdge(B,A) ] = nil 
                continue 
            end

            edges[ keyForEdge(A,B) ] = { from = pair[1], to = pair[2] }
            -- edgesAtoB[ keyForPos(A) ] = B

        end

    end
    for k, e in pairs(edges) do
        edgesAtoB[ keyForPos(e.from) ] = e.to
    end

    -- averageTranslation = averageTranslation/#TRIS
    totalMassDisp      = totalMassDisp/totalArea
    totalArea          = totalArea/2
    -- print("AVERAGE TRANSLATION!!!!:::",averageTranslation)
    -- print("TOTAL AREA!!!!!!       :::", totalArea)

    local reorder = {}

    local firstedge
    for k, edge in pairs(edges) do firstedge = edge break end

    reorder[1] = firstedge.from
    -- print("reorder 1: ",edge)
    -- PrintTable(firstedge)

    local looped = false

    local overflow = 300
    local ct = 0

    while not looped and not ( ct >= overflow ) do

        -- print("setting ts",#reorder + 1,"to", keyForPos( reorder[#reorder] ) )
        -- print("aka", edgesAtoB[ keyForPos( reorder[#reorder] ) ] )

        local vert = edgesAtoB[ keyForPos( reorder[#reorder] ) ]

        if vert == reorder[1] then
            looped = true
            break
        else
            reorder[#reorder + 1] = vert
        end

        ct = ct + 1

    end

    local offsets = {}

    local dirs = {}

    local normals = {}

    for i = 1, #reorder do

        local i0, i1, i2 = (i-2)%#reorder+1, i, i%#reorder+1

        local v0, v1, v2 = reorder[i0], reorder[i1], reorder[i2]

        local r0, r2 = v0 - v1, v2 - v1

        local perp = T1.matL:GetForward()

        local n0, n2 = perp:Cross(r0):GetNormalized(), r2:Cross(perp):GetNormalized()
        normals[i2] = n2 

        local bis = (n0+n2):GetNormalized()

        local bis2 = bis / bis:Dot(n0)

        offsets[i] = bis2

        dirs[i] = (v2-v1):GetNormalized()

    end

    -- PrintTable( PolyProjection(T1.matL, reorder) )
    C.polygons[ keyForNorm( T1.detN ) ] = {
        matL        = T1.matL,
        vertices    = PolyProjection(T1.matL, reorder),
        vertices3D  = reorder,
        offsets3D   = offsets,
        normals3D   = normals,
        dirs3D      = dirs,
        area        = totalArea,
        centroid    = totalMassDisp,
        physicsbone = physicsbone,
        convex      = convex
    }
    -- print(totalMassDisp)

    return C.polygons[ keyForNorm( T1.detN ) ]

end

local crosses = {}

function FocusEntity.RefreshMassCenter(poly, mc)

    local mc     = mc or FocusEntity.MassCenters[poly.physicsbone]

    local mcProj = mc + (poly.matL:GetTranslation()-mc):Dot(poly.matL:GetForward()) * poly.matL:GetForward()

    -- print("aklsdnfsdjkfnasdjk")
    -- print("mc!!:", mc, "mcp:", mcProj)

    local mcdist, mcdisp, withinCt = nil,nil,0

    -- print(mcProj)
    for i = 1, #poly.vertices do

        local v1, v2 = poly.vertices3D[i], poly.vertices3D[i%#poly.vertices+1]

        local d, v, l = util.DistanceToLine(v1, v2, mcProj)

        if mcdist then
            if d < mcdist then
                mcdist = d
                mcdisp = v
            end 
        else
            mcdist = d 
            mcdisp = v
        end

        local n = (v2-v1):Cross(mcProj-v1):Dot(poly.matL:GetForward())
        -- crosses[#crosses+1] = { dir = (v2-v1):Cross(mcProj), pos = v1 }
        -- print(n)
        withinCt = withinCt + ( n >= 0 and 1 or -1 )

    end

    -- print(withinCt, #poly.vertices)
    if math.abs(withinCt) == #poly.vertices then 
        poly.mcWithin = true 
    else
        poly.mcWithin = false
    end
    poly.mcDisp = mcdisp
    poly.mcPos  = mcProj
    poly.mcDist = mcdist

end

-- hook.Remove("PostDrawTranslucentRenderables", "gerp")
-- hook.Add("PostDrawTranslucentRenderables", "gerp", function()

--     for k, v in pairs(crosses) do
--         arrow(FocusEntity.WorldMatrix * v.pos, FocusEntity.WorldMatrixNoTR * v.dir:GetNormalized())
--     end

-- end)

function FocusEntity.WindPolygons( NORS, physicsbone, convex ) -- { k_detN = { tri, tri ... }, k_detN = { tri, tri ... }, ... }

    for k_detN, TRIS in pairs(NORS) do

        local poly = WindPolygon3D(TRIS, physicsbone, convex)
        FocusEntity.RefreshMassCenter(poly)

    end

end

function FocusEntity.SetEntity(ent)

    if FocusEntity.Entity == ent then return end

    FocusEntity.Thought = false
    FocusEntity.Locked = false
    FocusEntity.LockedTimestamp = 0

    FocusEntity.ShapeDataCompiled = false
    FocusEntity.OffsetDetermined = false
    FocusEntity.Entity = ent
    FocusEntity.SetPhysicalData()
    FocusEntity.SetShapeData()

    FocusEntity.WorldMatrices = {}
    FocusEntity.WorldMatricesInv = {}
    FocusEntity.WorldMatricesNoTR = {}
    FocusEntity.WorldMatricesInvNoTR = {}

    FocusEntity.PrevBonemat = {}
    FocusEntity.Moving = {}
    FocusEntity.CurrentlyMoving = false

    FocusEntity.ClkStart = CurTime()
    FocusEntity.Clk = 0 

    FocusEntity.LocalNormal = nil
    FocusEntity.FullFocusCoplane = nil
    FocusEntity.CoplanarFocusPolygons = {}
    FocusEntity.TempDat = {}
    FocusEntity.FocusPolygon = nil

    FocusEntity.Grid = { focalpoints = {} } 

end

local function bonemat(ent, id)

     return ent:GetBoneMatrix( ent:TranslatePhysBoneToBone(id) ) or ent:GetBoneMatrix(0) or Matrix()

end

function FocusEntity.RefreshWorldMatrix()

    local ent = FocusEntity.Entity

    if !IsValid(ent) then return end

    local pb = FocusEntity.tr.PhysicsBone + 1

    for i = 1, FocusEntity.PhysBoneCount do

        -- FocusEntity.Moving[i] = bonemat(ent, i-1) != ( FocusEntity.PrevBonemat[i] or Matrix() )
        -- FocusEntity.PrevBonemat[i] = bonemat(ent, i-1) or Matrix()

        -- if i == pb then FocusEntity.CurrentlyMoving = FocusEntity.Moving[i] end

        -- if !FocusEntity.Moving[i] and FocusEntity.Clk > 0.25 then return end

        FocusEntity.WorldMatrices[i]    = bonemat(ent, i-1) * FocusEntity.PropOffsetMatrixInv
        FocusEntity.WorldMatricesInv[i] = FocusEntity.WorldMatrices[i]:GetInverseTR()

        -- print(FocusEntity.WorldMatrices[i])

        FocusEntity.WorldMatricesNoTR[i]     = Matrix()
        FocusEntity.WorldMatricesNoTR[i]:SetAngles( FocusEntity.WorldMatrices[i]:GetAngles() )
        FocusEntity.WorldMatricesInvNoTR[i]  = Matrix()
        FocusEntity.WorldMatricesInvNoTR[i]:SetAngles( FocusEntity.WorldMatricesInv[i]:GetAngles() )

    end

    -- if !FocusEntity.CurrentlyMoving and FocusEntity.Clk > 0.25 then return end

    if type(FocusEntity.tr) == "table" then

        FocusEntity.WorldMatrix     = FocusEntity.WorldMatrices[ pb ]
        FocusEntity.WorldMatrixInv  = FocusEntity.WorldMatricesInv[ pb ]

        FocusEntity.WorldMatrixNoTR     = FocusEntity.WorldMatricesNoTR[ pb ]
        FocusEntity.WorldMatrixInvNoTR  = FocusEntity.WorldMatricesInvNoTR[ pb ]

    end

end

local function typGrid()

    return ALTING and "polar" or "cartesian"

end





local unitsperhashcell = 2

local function keyForCell(cx, cy, cz)
    return cx * 73856093 + cy * 19349663 + cz * 83492791
end

local function keyForCellPos(v)
    return keyForCell( 
        math.floor( v.x/unitsperhashcell ),
        math.floor( v.y/unitsperhashcell ),
        math.floor( v.z/unitsperhashcell ) 
    )
end

local function IndexPoints(T)

    local cells = {}

    for _, p in pairs(T) do

        local k = keyForCellPos(p)
        local c = cells[k]

        if not c then 
            c = {} 
            cells[k] = c
        end

        c[#c+1] = p 

    end

    return cells

end

local function BuildGridIndex(G)
    G.Cells = {
        tick    = IndexPoints(G.ticks),
        rayend  = IndexPoints(G.rayends)
    }
    G.ready = true
end

local function NearestInCells(cells, p, maxR)

    -- local best, bestsqr = nil, math.huge
    local best = nil
    local bestsqr = math.huge
    -- maxR = maxR or 4*CELLWIDTH -- expanding search aroond point p until radius is too big
    maxR = maxR or 8 -- expanding search aroond point p until radius is too big

    for r = 0, maxR do
        for ix = -r, r do
            for iy = -r, r do
                for iz = -r, r do

                    if math.max(math.abs(ix), math.abs(iy), math.abs(iz)) ~= r then continue end 
                    local c = cells[keyForCellPos(p + Vector(ix, iy, iz) * unitsperhashcell)]

                    if c then
                        for _, q in pairs(c) do

                            local D = q - p
                            local d = D:Dot(D)
                            -- print(bestsqr)
                            if d < bestsqr then best, bestsqr = q, d end

                        end
                    end
                end
            end
        end

        if best and bestsqr <= (r * unitsperhashcell) ^ 2 then break end
    end

    return best, bestsqr
end




function FocusEntity.RefreshFocalPoints()

    local fp = FocusEntity.Grid.focalpoints
    fp = {}

    local fpoly = FocusEntity.FocusPolygon

    if type(fpoly) != "table" then return end

    for _, vert in pairs(fpoly.vertices3D) do

        fp[ keyForPos(vert) ] = {pos = vert, type = "edge"}

    end

    local mc = fpoly.mcPos

    -- local fuckpos = Vector(24,12,12)
    -- fp[ keyForPos(fuckpos) ] = {pos = fuckpos, type = "masscenter"}

    if mc then

        if fpoly.mcWithin then

            fp[ keyForPos(mc) ] = {pos = mc, type = "masscenter"}

        else

            fp[ keyForPos(fpoly.mcDisp) ] = {pos = fpoly.mcDisp, type = "masscenteroff"}

        end

    end

    -- if type(fpoly.gridData) == "table" then -- mega slow

    --     local typ = typGrid()

    --     if type(fpoly.gridData[typ]) == "table" then

    --         print('gubbay')

    --         if type(fpoly.gridData[typ].ticks) == "table" then

    --             -- print("gabaloogagaga")

    --             for _, tick in pairs(fpoly.gridData[typ].ticks) do

    --                 if type(fp[ keyForPos(tick) ]) == "table" then continue end

    --                 fp[ keyForPos(tick) ] = {pos = tick, type = "tick"}

    --             end

    --             for _, rayend in pairs(fpoly.gridData[typ].rayends) do

    --                 if type(fp[ keyForPos(rayend) ]) == "table" then continue end

    --                 fp[ keyForPos(rayend) ] = {pos = rayend, type = "rayend"}

    --             end

    --         end

    --     end

    -- end



    -- for k_pos, vert in pairs(fp) do

    --     vert.lenSQR = ( FocusEntity.LocalHitPos - vert.pos ):LengthSqr() 

    -- end

    -- local closest

    -- for k_pos, vert in pairs(fp) do

    --     if !closest then closest = k_pos continue end 

    --     closest = vert.lenSQR < fp[closest].lenSQR and k_pos or closest

    -- end

    -- FocusEntity.Grid.focalpoint = fp[closest]

    -- local matW = FocusEntity.WorldMatrices[fpoly.physicsbone]

    -- FocusEntity.Grid.focalpoint.posW = matW * fp[closest].pos

    -- print(closest)

    local lhp = FocusEntity.LocalHitPos

    local best, bestsqr = nil, math.huge

    for _, vert in pairs(fp) do

        local d = (lhp-vert.pos):LengthSqr()
        vert.lensqr = d
        if d < bestsqr then 
            best = vert
            bestsqr = d
        end

    end
    if not best then return end

    local G = fpoly.gridData and fpoly.gridData[typGrid()]
    if G and G.ready then

        -- print("is that a gubby :<")
        if !G.qPos or (G.qPos - lhp):LengthSqr() > 1e-6 then
            G.qPos = Vector(lhp) -- this copies da vector ig
            G.qTick, G.qTickSqr = NearestInCells( G.Cells.tick  , lhp )
            G.qRay , G.qRaySqr  = NearestInCells( G.Cells.rayend, lhp )
        end
        
        local EPS = 0.01
        if G.qTick and G.qTickSqr < bestsqr - EPS then
            best, bestsqr = { pos = G.qTick, type = "tick", lenSQR = G.qTickSqr }, G.qTickSqr
        end
        if G.qRay and G.qRaySqr < bestsqr - EPS then
            best, bestsqr = { pos = G.qRay, type = "rayend", lenSQR = G.qRaySqr }, G.qRaySqr
        end

    end

    FocusEntity.Grid.focalpoint = best
    best.posW = FocusEntity.WorldMatrices[fpoly.physicsbone] * best.pos

end

hook.Remove("Think", PS_.."Run")
hook.Add("Think", PS_.."Run", function()

    -- print(collectgarbage("count"))

    ISTOOLGUN = LocalPlayer():GetActiveWeapon():GetClass() == "gmod_tool"

    if ( cBool("anyweapon") or ISTOOLGUN ) and cBool("enable") then 
        ENABLED = true
    else
        ENABLED = false 
        peepeeNoPress()
        return 
    end

    ISLOCKABLE = 
        ( IsValid(FocusEntity.Entity) ) and
        ( FocusEntity.FocusPolygon != nil ) and
        ( ENABLED ) and
        ( ( cBool("toolgunuseonly") and ISTOOLGUN ) or !cBool("toolgunuseonly") )

    -- if ISLOCKABLE then
    --     local p = FocusEntity.Grid.focalpoint.pos
    --     FocusEntity.Grid.focalpoint.pos = p + Vector(0,0,1)
    --     print(FocusEntity.Grid.focalpoint.pos)
    -- end

    -- print(
    --     ( IsValid(FocusEntity.Entity) ),
    --     ( FocusEntity.FocusPolygon != nil ),
    --     ( ENABLED ),
    --     ( ( cBool("toolgunuseonly") and ISTOOLGUN ) or !cBool("toolgunuseonly") )
    -- )

    local tr = FocusEntity.tr

    if type(tr) != "table" then return end

    if FocusEntity.Locked then return end

    FocusEntity.SetEntity(tr.Entity)
    FocusEntity.Clk = CurTime() - FocusEntity.ClkStart

    -- print(FocusEntity.ShapeDataCompiled,FocusEntity.OffsetDetermined)
    if !FocusEntity.ShapeDataCompiled then return end

    if !FocusEntity.OffsetDetermined then return end

    -- FocusEntity.RefreshWorldMatrix()
    -- print("asdfsssd")
    if tr.Entity:IsWorld() then return end
    -- print("asdfd")

    -- print("asdf")

    local w2l = FocusEntity.WorldMatricesInv[ tr.PhysicsBone + 1 ]

    if not w2l then return end

    FocusEntity.lhpPrev     = FocusEntity.LocalHitPos or Vector()
    FocusEntity.LocalHitPos = w2l * ( tr.HitPos - tr.HitNormal * DIST_EPSILON )
    FocusEntity.lhpChanged  = (FocusEntity.LocalHitPos - FocusEntity.lhpPrev):LengthSqr() > 0
    -- print(FocusEntity.lhpChanged)

    local twist = Matrix()
    twist:SetAngles( w2l:GetAngles() )

    -- local pos = 

    local detN = twist * tr.HitNormal
    local orgD = ( FocusEntity.LocalHitPos ):Dot( detN )
    -- local orgD = ( LocalHitPos ):Dot( detN )

    local significantViewChange = false
    if type(FocusEntity.FullFocusCoplane) != "table" then significantViewChange = true end
    -- print("gump")

    if not detN then return end

    local k_detN = keyForNorm( detN )
    local k_orgD = keyForDist( orgD )

    local B = FocusEntity.PerBone[ tr.PhysicsBone+1 ]

    if type(B) != "table" then return end

    -- print("ger")
    if B.ConvexCount == 1 then 

        FocusEntity.FocusConvex = 1

        -- FocusEntity.FocusPolygon = k_detN

        local C = B.PerConvex[ 1 ]

        FocusEntity.FocusPolygon = C.polygons[k_detN]

        FocusEntity.FullFocusCoplane = { C.normals[ k_detN ] }

        FocusEntity.CoplanarFocusPolygons = { C.polygons[ k_detN ] }

    else

        if FocusEntity.OrgDistance and FocusEntity.LocalNormal then

            local deviated = (detN-FocusEntity.LocalNormal):LengthSqr() > 0.001
            -- print(deviated)
            -- if detN:Dot(FocusEntity.LocalNormal) < 1 - 1e-4 then
            if deviated then
                -- print("detn changed")
                significantViewChange = true
            elseif math.abs( orgD - FocusEntity.OrgDistance ) > 0.01 then
                -- print("orgdist changed")
                significantViewChange = true
            end

        else

            FocusEntity.LocalNormal = detN
            FocusEntity.OrgDistance = orgD

        end

        -- local potentialConvexes

        if significantViewChange then

            FocusEntity.Grid = { focalpoints = {} } 

            -- print("ababa")

            FocusEntity.LocalNormal = detN
            FocusEntity.OrgDistance = orgD

            -- local k_detN = keyForNorm( detN )
            -- local k_orgD = keyForDist( orgD )

            local blah = k_detN.."|"..k_orgD

            -- print(blah, orgD, k_orgD)
            local convexes = FocusEntity.PerBone[tr.PhysicsBone + 1].NormAndDForConvex[ blah ]

            -- print("checkingconvexes")
            local invalid = type(convexes) != "table"
            -- print(invalid and "XXX " or "___ ".."tracedist: ", invalid and "_" or ("qty "..#convexes),orgD,keyForDist(orgD), blah)
            if type(convexes) != "table" then 
                print( "invalid calcconvex" ) 
                return 
            end

            FocusEntity.CoplanarFocusPolygons = {}
            FocusEntity.FullFocusCoplane = convexes

            local potentialConvexCount = 0
            for k, v in pairs(convexes) do potentialConvexCount = potentialConvexCount + 1 end

            -- PrintTable(convexes)
            -- print("NUMCONVEXES",potentialConvexCount)

            if potentialConvexCount == 1 then 

                for k, v in pairs(convexes) do FocusEntity.FocusConvex = k break end

                -- print("ONLY ONE CONVEX ON THIS COPLANE AND ITS "..FocusEntity.FocusConvex)
                -- print(FocusEntity.FocusConvex)
                -- timer.Simple(0, function() print(FocusEntity.FocusConvex) end)

                FocusEntity.MultiplePotentialConvexes = false

                local C = B.PerConvex[ FocusEntity.FocusConvex ]

                FocusEntity.CoplanarFocusPolygons[FocusEntity.FocusConvex] = C.polygons[k_detN]

            else
                FocusEntity.FocusConvexPREV = FocusEntity.FocusConvex or FocusEntity.FocusConvexPREV
                -- print("FCPREV:",FocusEntity.FocusConvexPREV) 
                FocusEntity.FocusConvex = nil
                -- print("MULTIPLE POTENTIAL CONVEXES ON THIS COPLANE")
                FocusEntity.MultiplePotentialConvexes = true
            end

        end 

        if FocusEntity.MultiplePotentialConvexes then

            if FocusEntity.lhpChanged then 
                -- print("FCPR2V:",FocusEntity.FocusConvexPREV)
                FocusEntity.FocusConvexPREV = FocusEntity.FocusConvex or FocusEntity.FocusConvexPREV
                FocusEntity.FocusConvex = nil 
            end -- focus convex may have changed if the cursor moved

            for convex_ind, v in pairs(FocusEntity.FullFocusCoplane) do

                local C = B.PerConvex[ convex_ind ]

                if FocusEntity.FocusConvex then continue end

                if type( C.polygons[k_detN] ) != "table" then continue end -- WHAT. WHAT. WHAT. WHAT. WHAT. WHAT. WHAT. WHAT. 

                local vertices = C.polygons[k_detN].vertices3D

                local sumcross = 0

                local lhp = FocusEntity.LocalHitPos

                local qtyv = #vertices

                -- print("==== conv "..convex_ind.." ============")

                -- eps is 0.1 for keyforpos fyi

                local distfromplane = (lhp-vertices[1]):Dot( FocusEntity.LocalNormal )
                -- print( "dist:",distfromplane )

                for i = 1, qtyv do

                    local p1, p2 = vertices[i], vertices[i%qtyv+1]
                    local edge = p2 - p1
                    -- print(i%qtyv+1, i)

                    local cross = (edge):Cross(lhp-p1):Dot(FocusEntity.LocalNormal)

                    -- print( "cross"..i..":",cross )

                    if math.abs(cross) <= 0.05 then --disregard 1 edge if its just toooo close
                        qtyv = qtyv-1 
                        continue
                    end

                    if cross > 0 then
                        sumcross = sumcross + 1
                    elseif cross < 0 then
                        sumcross = sumcross - 1
                    else
                        sumcross = sumcross + 0
                    end

                end
                -- print( "sumcross:", sumcross, qtyv, math.abs(sumcross) == qtyv )

                if math.abs(sumcross) == qtyv then

                    FocusEntity.FocusConvex = convex_ind
                    -- print("FOCUS CONVEX FOUND!!!!:",FocusEntity.FocusConvex)

                end

            end

        end

    end

    -- print("PENIS1",FocusEntity.FocusConvexPREV)
    if not FocusEntity.FocusConvex then FocusEntity.FocusConvex = FocusEntity.FocusConvexPREV return end

    FocusEntity.FocusPolygon = B.PerConvex[ FocusEntity.FocusConvex ].polygons[k_detN]

    -- if type(FocusEntity.FullFocusCoplane) != "table" then return end

    -- print("COPLANAR SELECTION:")
    -- PrintTable(FocusEntity.FullFocusCoplane)
    -- print(CurTime())

    -- ::noCalcConvex::

    FocusEntity.RefreshFocalPoints()


    FocusEntity.Thought = true

end)

-- print(CLGetPhysicsObject(ent))

local function text(text, pos, sub, color)
    sub = sub or false

    local tsc = ( pos + vector_up * TimedSin(0.25, 0, 1, 0) ):ToScreen()
    cam.Start2D()
        surface.SetFont( !sub and "ChatFont" or "DefaultFixedDropShadow" )
        local tW, tH = surface.GetTextSize( text )
        surface.SetTextPos( tsc.x - tW/2, tsc.y - tH/2 )
        surface.DrawText(tostring(text))
    cam.End2D()

end

-- FocusEntity.OffsetPolygons[convex][normal]
-- FocusEntity.OffsetPolygons[convex][normal]
 
local function add2D( t1, t2 ) return { x = t1.x + t2x, y = t1.y + t2.y } end

local function scale2D( k, t ) return { x = k * t.x, y = k * t.y } end

-- local function OffsetPolygon( poly, d )

--     local polygon = table.Copy( poly )

--     polygon.matL:SetTranslation( polygon.matL:GetTranslation() + polygon.matL:GetForward() * d )

--     return 

-- end

-- local function drawFaceGrid(polygon)

-- end

local function puckline2d(x1,y1,x2,y2)

    surface.SetDrawColor( color_white )
    surface.DrawLine( v1.x+n, v1.y+n, v2.x+n, v2.y+n )

end

local function drawFace(polygon)

    if type(polygon) != "table" then return end

    local pb = polygon.physicsbone
    polygon.matW = FocusEntity.WorldMatrices[pb] * polygon.matL

    local dot0 = (EyePos() - polygon.matW:GetTranslation()):GetNormalized():Dot(polygon.matW:GetForward())

    local fp = FocusEntity.FocusPolygon

    local dot01 = 1

    if fp.matW then

        local lr = cNum("facesmoothing")

        dot01 = math.Clamp( ( fp.matW:GetForward():Dot(polygon.matW:GetForward()) - lr )*(1/(1-lr)), 0, 1 )
        -- print("adjfnsdk")

    end

    if cBool("faceculling") and dot0 <= 0 then return end

    local cur = polygon == fp
    local curBone = pb == FocusEntity.tr.PhysicsBone + 1
    local curC = polygon.convex == FocusEntity.FocusConvex

    -- local a = cur and 150 or ( curBone and 50 or 15 ) * ( curC and 1 or 0.5 ) * dot01

    local a = 10

    if a < 1 then return end

    local ang = polygon.matW:GetAngles()
    ang:RotateAroundAxis( ang:Forward(), 90 )   
    ang:RotateAroundAxis( ang:Right(), 90 ) 

    local pos = polygon.matW:GetTranslation()

    local dot = polygon.matW:GetForward():Dot(vector_up)
    local dot2 = dot*0.5+0.5

    -- arrow(pos, polygon.matW:GetRight())

    local col = HSVToColor( 
        Lerp( dot2, -50, HSVcolors_fgcorange.h ) + ( curC and 0 or 175 ), 
        -- HSVcolors_fgcorange.h + ( polygon.convex == FocusEntity.FocusConvex and 0 or 175 ) , 
        ( 0.7 - 0.3*dot2 ) * (cur and 0.5 or 1) * (curC and 1 or 0.5), 
        cur and 1 or 0.5 + 0.5*dot2
    )
    col.a = a

    local numv = #polygon.vertices

    cam.IgnoreZ( cBool("drawfacesignorez") )
    cam.Start3D2D(pos, ang, 1)

        surface.SetDrawColor( col:Unpack() )
        draw.NoTexture()
        surface.DrawPoly( polygon.vertices )

    cam.End3D2D()
    cam.IgnoreZ( false )

    local dropshadowlength = cNum("dropshadowlength")

    local lineopacity = 255 * cNum("lineopacity")

    local dropshadowopacity = lineopacity * cNum("dropshadowopacity")

    surface.SetDrawColor( 0, 0, 0, dropshadowopacity )

    pos = pos - fp.matW:GetForward() * dropshadowlength
    for i = 1, 2 do 

        cam.IgnoreZ( cBool("drawfacesignorez") )
        cam.Start3D2D(pos, ang, 1)

        for i = 1, #polygon.vertices do

            local v1, v2 = polygon.vertices[i], polygon.vertices[i%numv+1]

            local n = -0.5

            surface.DrawLine( v1.x+n, v1.y+n, v2.x+n, v2.y+n )

        end

        surface.SetDrawColor( 255, 255, 255, lineopacity )

        cam.End3D2D()
        cam.IgnoreZ( false )

        pos = pos + fp.matW:GetForward() * dropshadowlength

    end

end

-- function FocusEntity.DebugCoplaneRendering( fullcoplane, detN ) -- { num convexid = { num tri, num tri, ... } ... }

--     -- print("abababa", fullcoplane)

--     if type(fullcoplane) != "table" then return end

--     local numconvexes = 0
--     for k, v in pairs(fullcoplane) do numconvexes = numconvexes + 1 end

--     local perconvexes = FocusEntity.PerBone[ FocusEntity.tr.PhysicsBone + 1 ].PerConvex
--     local normal = FocusEntity.tr.HitNormal

--     -- local T1 = perconvexes[fullcoplane[1]].fullcoplane[1][1]
--     -- print("TEEEEEEEEE1:",detN)
--     local twist = Matrix()
--     twist:SetAngles( FocusEntity.WorldMatrixInv:GetAngles() )
--     detN = twist * normal

--     local T1

--     local B = FocusEntity.PerBone[ FocusEntity.tr.PhysicsBone+1 ]

--     local C = B.PerConvex[ FocusConvex() ]

--     if type(B.vertices) != "table" then return end

--     -- for bone_ind, bone in pairs(FocusEntity.PerBone) do

--     --     for convex_ind, convex in pairs(bone.PerConvex) do

--     --         for k_detN, poly in pairs(convex.polygons) do

--     --             local difR = poly.matL:GetRight()-FocusEntity.FocusPolygon.matL:GetRight()

--     --             -- local difU = poly.matL:GetUp()-FocusEntity.FocusPolygon.matL:GetUp()

--     --             -- print(dif:LengthSqr())
--     --             if math.abs( difR:LengthSqr() ) < 0.001 then
--     --             -- if math.abs(dif.z) < 0.01 or math.abs(dif.y) < 0.01 or math.abs(dif.x) < 0.001 then

--     --                 drawFace(poly)

--     --             end

--     --         end

--     --     end

--     -- end

--     drawFace(FocusEntity.FocusPolygon)

--     -- for bone_ind, bone in pairs(FocusEntity.PerBone) do -- per all

--     --     for convex_ind, convex in pairs(bone.PerConvex) do

--     --         for k_detN, poly in pairs(convex.polygons) do

--     --             drawFace(poly)

--     --         end

--     --     end

--     -- end

--     -- for bone_ind, bone in pairs(FocusEntity.PerBone) do -- per area

--     --     for convex_ind, convex in pairs(bone.PerConvex) do

--     --         for k_detN, poly in pairs(convex.polygons) do

--     --             local difA = math.abs(poly.area - FocusEntity.FocusPolygon.area)
--     --             local checkA = difA < 0.01

--     --             local difF = poly.matL:GetForward()-FocusEntity.FocusPolygon.matL:GetForward()
--     --             local checkF = math.abs(difF.z) < 0.01 or math.abs(difF.y) < 0.01 or math.abs(difF.x) < 0.01

--     --             if checkA and checkF then

--     --                 drawFace(poly)

--     --             end

--     --         end

--     --     end

--     -- end

--     if true then return end

--     if !cBool("drawfullconvex") then

--         drawFace(FocusEntity.FocusPolygon)

--     else
--         -- print("agajksdfnsdfkn")

--         for k, poly in pairs(C.polygons) do drawFace(poly) end

--         if cBool("drawpseudonormals") then

--             for k_pos, vert in pairs(B.vertices) do

--                 if type( vert.pseudoNormal ) != "Vector" then continue end

--                 arrow( FocusEntity.WorldMatrix * vert.pos, FocusEntity.WorldMatrixNoTR * vert.pseudoNormal, 16, colors_fgcgray )

--             end

--         end

--     end

--     for convex_ind, triangles in pairs(fullcoplane) do

--         local C = perconvexes[convex_ind]
--         local P = C.polygons[ keyForNorm(detN) ]

--         if type(P) == "table" then

--             -- print(P.area , FocusEntity.FocusPolygon.area)

--             if math.abs(P.area - FocusEntity.FocusPolygon.area) < 0.01 or numconvexes < 10 then
--                 drawFace(P)
--             end

--         end

--     end

--     if true then return end

--     -- drawFace(FocusEntity.FocusPolygon)

--     for convex_ind, triangles in pairs(fullcoplane) do

--         local perconvex = perconvexes[convex_ind]
--         local polygon = perconvex.polygons[ keyForNorm(detN) ]

--         if cBool("drawfaces") then

--             -- local polygon = perconvex.polygons[ keyForNorm(detN) ]
--             if type(polygon) != "table" then continue end

--             polygon.matW = FocusEntity.WorldMatrix * polygon.matL

--             local ang = polygon.matW:GetAngles()
--             ang:RotateAroundAxis( ang:Forward(), 90 )   
--             ang:RotateAroundAxis( ang:Right(), 90 ) 

--             local pos = polygon.matW:GetTranslation() + normal * DIST_EPSILON

--             cam.IgnoreZ( cBool("drawfacesignorez") )
--             cam.Start3D2D(pos, ang, 1)

--                 surface.SetDrawColor( 255, 131, 0, 30 )
--                 draw.NoTexture()
--                 surface.DrawPoly( polygon.vertices )

--             cam.End3D2D()

--             if cBool("drawvertexindeces") then

--                 ang:RotateAroundAxis( ang:Right(), 180 )

--                 local sc = 0.05

--                 cam.Start3D2D(pos, ang, sc)

--                     for k, v in pairs(polygon.vertices) do 

--                         local tW, tH = surface.GetTextSize( tostring(k) )

--                         surface.SetFont( "DefaultFixedDropShadow" )
--                         surface.SetTextColor( 255, 255, 255 )
--                         surface.SetTextPos( -v.x/sc - tW/2, v.y/sc - tH/2 + TimedCos(0.3, 0, 1/sc, k) )
--                         -- surface.SetTextPos( (-v.x - tW/2)/sc, (v.y - tH/2)/sc ) 
--                         surface.DrawText( k )

--                     end

--                 cam.End3D2D()

--             end

--             cam.IgnoreZ( false )

--         end

--         if cBool("drawfaceindeces") then
        
--             for k, tri in pairs(triangles) do

--                 -- print(convex_ind, tri)

--                 local T = perconvex.triangles[tri]

--                 if type(T) != "table" then return end

--                 T.matW = FocusEntity.WorldMatrix * T.matL

--                 local ang = T.matW:GetAngles()
--                 ang:RotateAroundAxis( ang:Forward(), 90 )   
--                 ang:RotateAroundAxis( ang:Right(), 90 ) 

--                 local pos = T.matW:GetTranslation() + T.matW:GetForward() * DIST_EPSILON

--                 surface.SetFont( "ChatFont" )
--                 local tW, tH = surface.GetTextSize( tostring(tri) )
--                 local padX, padY = 5, 5

--                 if not T.faceIndexCardSize then
--                     local area = 0.5 * T.det:Length()
--                     local maxlen = 0
--                     for _, pair in pairs({{T.p1,T.p2},{T.p2,T.p3},{T.p3,T.p1}}) do
--                         maxlen = math.max(maxlen, (pair[2]-pair[1]):LengthSqr())
--                     end
--                     local rad = 2/3 * area / math.sqrt(maxlen)
--                     local diag = math.sqrt( ( tW/2 + padX )^2 + ( tH/2 + padY )^2 )
--                     T.faceIndexCardSize = rad/diag
--                 end

--                 local pos = T.matW:GetTranslation() + T.matW:GetForward() * DIST_EPSILON
--                 ang:RotateAroundAxis( ang:Right(), 180 ) 

--                 cam.IgnoreZ( cBool("drawfacesignorez") )
--                 cam.Start3D2D(pos, ang, T.faceIndexCardSize)

--                     surface.SetDrawColor( 0, 0, 0, 100 )
--                     surface.DrawRect( -tW / 2 - padX, -tH / 2 -padY, tW + padX * 2, tH + padY * 2 )
--                     draw.SimpleText( tostring(tri), "ChatFont", -tW / 2, -tH / 2, color_white )
--                     -- PrintTable(proj)

--                 cam.End3D2D()
--                 cam.IgnoreZ( false )

--             end

--         end

--     end

-- end

local function iconstr(icon, res) 
    res = res or 16 
    return "icon"..res.."/"..icon..".png"
end

storedicons = {}
local function icon(icon)
    if not storedicons[icon] then
        storedicons[icon] = Material(iconstr(icon))
    end
    return storedicons[icon]
end

function FocusEntity.RefreshTrace()

    local tr = LocalPlayer():GetEyeTrace()

    FocusEntity.tr = tr

    return FocusEntity.tr.Entity

end

function FocusEntity.HasFrameBeenPrepped()

    -- print("ASDNDSF") 

    if type(FocusEntity.FocusPolygon) != "table" then return false end -- reliable check ig

    -- print("ASDNDSFAAAAAAAAAAAAAAAAAAAAAAAA")

    return true

end

function FocusEntity.PrepFrame()

    if !FocusEntity.Locked then

        if FocusEntity.Entity != FocusEntity.RefreshTrace() then return false end -- prevents that tiny snapping artifact when switching ents

    end

    if !IsValid(FocusEntity.Entity) or !FocusEntity.ShapeDataCompiled then return false end

    FocusEntity.RefreshWorldMatrix()

    if !FocusEntity.HasFrameBeenPrepped() then return false end -- bleh

    return true

end

-- print(Entity(1391)["GetColor"](Entity(1391))) -- i'll be damned

-- hook.Remove("PostDrawTranslucentRenderables", PS_.."Draw")
-- hook.Add("PostDrawTranslucentRenderables", PS_.."Draw", function()

--     -- if !FocusEntity.PrepFrame() then return end

--     if !FocusEntity.HasFrameBeenPrepped() then return end

--     for bone_index, WorldMatrix in pairs(FocusEntity.WorldMatrices) do

--         local WorldMatrixInv = FocusEntity.WorldMatricesInv[bone_index-1]

--         if cBool("drawiconboneindex") then

--             local ri = WorldMatrix:GetTranslation()

--             text(bone_index-1, ri, (ri-EyePos()):LengthSqr() > 10000)

--         end

--         -- text("MC", mC, (mC-EyePos()):LengthSqr() > 10000)
--         if cBool("drawiconmasscenter") then

--             local mC = WorldMatrix * FocusEntity.MassCenters[bone_index]

--             cam.IgnoreZ( true )
--             cam.Start3D()
--                 cam.IgnoreZ( true )
--                 render.SetMaterial( icon("anchor") )
--                 render.DrawSprite( mC, 4, 4 )
--             cam.End3D()
--             cam.IgnoreZ( false )

--         end

--     end

--     if cBool("drawhitnormals") then

--         arrow( FocusEntity.tr.HitPos, FocusEntity.tr.HitNormal, 10, Color(255,255,0), nil, true )

--     end
--     -- print(FocusEntity.FullFocusCoplane)

--     -- FocusEntity.DebugCoplaneRendering( FocusEntity.FullFocusCoplane, FocusEntity.LocalNormal )

-- end)

local function puckline(v1, v2, r,g,b,a, thickness, shadow)

    r,g,b,a = r or 255, g or 255, b or 255, a or cNum("lineopacity")*255
    thickness = thickness or 1
    if type(shadow) != "boolean" then shadow = cBool("drawlineshadows") end

    local tsc1, tsc2 = v1:ToScreen(), v2:ToScreen()

    if !(tsc1.visible or tsc2.visible) then return end

    if not (tsc1.visible and tsc2.visible) then -- clipping time

        -- print("raydata:")
        -- PrintTable({
        --     tsc1.visible and v1 or v2,
        --     tsc1.visible and (v2-v1):GetNormalized() or (v1-v2):GetNormalized(),
        --     EyePos() + EyeVector()*DIST_EPSILON, 
        --     EyeVector()})

        local int = util.IntersectRayWithPlane(
            tsc1.visible and v1 or v2,
            tsc1.visible and (v2-v1):GetNormalized() or (v1-v2):GetNormalized(),
            EyePos() + EyeVector()*DIST_EPSILON, 
            EyeVector()
        )

        if not int then return end

        if tsc1.visible then 
            tsc2 = int:ToScreen()
        else
            tsc1 = int:ToScreen()
        end

    end

    local drop = 0

    if shadow then
        -- surface.SetDrawColor(r/4,g/4,b/4,a/2)
        surface.SetDrawColor(0,0,0,a*0.75)
        drop = 2
    else
        surface.SetDrawColor(r,g,b,a)
    end

    for i = 1, 2 do

        if thickness != 0 then

            local perp = Vector(tsc2.x-tsc1.x,tsc2.y-tsc1.y,0):Cross(Vector(0,0,1)):GetNormalized()
            local d = 1.5
            local dx, dy = perp.x * d, perp.y * d
            for i = 1, thickness do
                local m = (- i + thickness/2)*2+1
                surface.DrawLine( 
                    tsc1.x + dx * m + drop , 
                    tsc1.y + dy * m + drop , 
                    tsc2.x + dx * m + drop , 
                    tsc2.y + dy * m + drop
                )
            end

        else

            surface.DrawLine( 
                tsc1.x + drop,
                tsc1.y + drop,
                tsc2.x + drop,
                tsc2.y + drop 
            )

        end

        if !shadow then break end

        surface.SetDrawColor(r,g,b,a)
        drop = 0
    end
end

local cachedMats = {}

local function mat( path )

    if type(cachedMats[path]) != "IMaterial" then
        cachedMats[path] = Material(path)
    end

    return cachedMats[path]

end

local function pucksprite( v, sprite, size, r,g,b,a, shadow )

    sprite = sprite or "bullet_error"
    sprite = "icon16/"..sprite..".png"
    size = size or (ScrW()*1/60)
    shadow = shadow or true
    r,g,b,a = r or 255,g or 255,b or 255,a or 255

    -- cam.Start3D()
    --     render.SetMaterial( mat(sprite) )
    --     render.DrawSprite( v, size, size, color_white )
    -- cam.End3D()

    local tsc = v:ToScreen()

    -- if FocusEntity.Locked then
    --     tsc.x = ScrW()/2
    --     tsc.y = ScrH()/2
    -- end

    surface.SetMaterial( mat(sprite) )

    local ts = FocusEntity.LockedTimestamp
    local bump = 20

    if not ts then return end

    local tmax = 0.2
    local t = math.max(ts-CurTime()+tmax, 0)*(1/tmax)

    local rad = size/8 * (1 + t*8)

    local vez = math.floor(rad) + 2

    for i = 1, vez do

        local rx = rad * math.cos(i/vez * math.pi * 2)
        local ry = rad * math.sin(i/vez * math.pi * 2)

        surface.SetDrawColor( r*0.25,g*0.25,b*0.25,a/2 )
        surface.DrawTexturedRect( tsc.x - size/2 + rx, tsc.y - size/2 + ry, size, size )

    end

    surface.SetDrawColor( r,g,b,a )
    surface.DrawTexturedRect( tsc.x - size/2, tsc.y - size/2, size, size )

    local ringscale = 4 * math.sin( (1-t)*3 )

    surface.SetMaterial( mat("effects/select_ring") )
    surface.SetDrawColor( 255,255,255,255*t )
    surface.DrawTexturedRect( tsc.x - size*ringscale/2, tsc.y - size*ringscale/2, size*ringscale, size*ringscale )

end

local function MakeWorldSpaceAABB(pb, physical)

    local WmatNT = FocusEntity.WorldMatricesNoTR[pb]
    local TR = FocusEntity.WorldMatrices[pb]:GetTranslation()

    local V = (physical==true) and 
              FocusEntity.PerBone[pb].PerConvex[FocusEntity.FocusConvex].vertices or
              FocusEntity.PhysicalAABBsVerts[pb]


    local toptable = physical and FocusEntity.PerBone[pb].PerConvex or {V}

    local m = Vector( math.huge, math.huge, math.huge )
    local M = Vector(-math.huge,-math.huge,-math.huge )

    -- if physical then

    for _, c in pairs(toptable) do
        
        for k, v in pairs(c.vertices or c) do

            -- PrintTable(toptable)
            -- print(physical, v.pos, v)

            local vw = WmatNT * (physical and v.pos or v)

            m = Vector(
                math.min( m.x, vw.x ),
                math.min( m.y, vw.y ),
                math.min( m.z, vw.z )
            )

            M = Vector(
                math.max( M.x, vw.x ),
                math.max( M.y, vw.y ),
                math.max( M.z, vw.z )
            )

        end

    end

    -- else

        -- for k, v in pairs(V) do

        --     local vw = WmatNT * (physical and v.pos or v)

        --     m = Vector(
        --         math.min( m.x, vw.x ),
        --         math.min( m.y, vw.y ),
        --         math.min( m.z, vw.z )
        --     )

        --     M = Vector(
        --         math.max( M.x, vw.x ),
        --         math.max( M.y, vw.y ),
        --         math.max( M.z, vw.z )
        --     )

        -- end

    -- end

    return m+TR, M+TR

end

local function SetWorldSpaceAABB(pb, physical)

    FocusEntity.PhysicalWorldAABBs[pb] = {MakeWorldSpaceAABB(pb, physical)}

    local AABBs = FocusEntity.PhysicalWorldAABBs[pb]
    local hyp = AABBs[2]-AABBs[1]
    FocusEntity.PhysicalWorldAABBsSize[pb] = Vector(hyp.x,hyp.y,hyp.z)

    FocusEntity.PhysicalWorldAABBsVerts[pb] = boxVertsLocal( unpack(FocusEntity.PhysicalWorldAABBs[pb]) )
    return FocusEntity.PhysicalWorldAABBsVerts[pb]

end

local AXES = {
    { s = "x", dir = "GetForward", pairs = {{"xyz","Xyz"},{"xYz","XYz"},{"xyZ","XyZ"},{"xYZ","XYZ"}}, flip =  1 },
    { s = "y", dir = "GetRight",   pairs = {{"xyz","xYz"},{"Xyz","XYz"},{"xyZ","xYZ"},{"XyZ","XYZ"}}, flip = -1 },
    { s = "z", dir = "GetUp",      pairs = {{"xyz","xyZ"},{"Xyz","XyZ"},{"xYz","xYZ"},{"XYz","XYZ"}}, flip =  1 },
}

local function DrawWorldSpaceAABB(pb, r,g,b,a, physical)

    if !cBool("drawworldspaceaabb") then return end

    r,g,b,a = r or 255, g or 0, b or 0, a or 255

    physical = physical or false

    SetWorldSpaceAABB(pb, physical) -- move this to `think` at some point

    V = FocusEntity.PhysicalWorldAABBsVerts[pb]
    
    if type(V) != "table" then return end

    PAIRS = {
        { V.xyz, V.Xyz },
        { V.xYz, V.XYz },
        { V.xyZ, V.XyZ },
        { V.xYZ, V.XYZ },
        { V.xyz, V.xYz },
        { V.Xyz, V.XYz },
        { V.xyZ, V.xYZ },
        { V.XyZ, V.XYZ },
        { V.xyz, V.xyZ },
        { V.Xyz, V.XyZ },
        { V.xYz, V.xYZ },
        { V.XYz, V.XYZ }
    }

    for k, v in pairs(PAIRS) do
        puckline(v[1], v[2], r,g,b,a, 1, false )
    end

end

local function SmartSnapianBoneAABB(pb, r,g,b,a)

    local Wmat = FocusEntity.WorldMatrices[pb]

    local V = FocusEntity.PhysicalAABBsVerts[pb]

    local S = FocusEntity.PhysicalAABBsSize[pb]

    local VW = {}

    for k, v in pairs(V) do
        VW[k] = Wmat * v
    end

    local len = 3

    -- local col = Color(0, 0, 255, 255)

    for _, Taxis in pairs(AXES) do

        local len = math.max(S[Taxis.s]*0.05,4)

        if S[Taxis.s] < len*2 then
            for _, pair in ipairs(Taxis.pairs) do
                puckline(VW[pair[1]], VW[pair[2]] ,r,g,b,a, 1, false )
            end
        else
            local dir = Wmat[Taxis.dir](Wmat)
            -- print(dir)
            for _, pair in ipairs(Taxis.pairs) do
                puckline(VW[pair[1]], VW[pair[1]] + dir * len * Taxis.flip ,r,g,b,a, 1, false )
                puckline(VW[pair[2]], VW[pair[2]] - dir * len * Taxis.flip ,r,g,b,a, 1, false )
            end
        end

    end

end


local function EdgeCollapseWidth( v1, v2, o1, o2 )

    local collapsewidth

    local E0 = v2-v1
    local D  = o2-o1
    local DD = D:Dot(D)

    if DD < 1e-8 then 
        collapsewidth = math.huge
    end

    local collapsewidth = -(E0:Dot(D)) / DD

    return collapsewidth

end

local function parametricray(FP, vI, D, vE, pE) -- try to provide vE and pE Please . :)

    local ph = D
    local O = vI
        -- print(O)

    if type(vE) != "table" then -- ts should be unecessary ^^^

        vE, pE = {}, {}

        local numv = #FP.vertices3D

        for n1=1, numv do

            local n2 = n1%numv+1

            local v1 = FP.vertices3D[n1]
            local v2 = FP.vertices3D[n2]

            vE[n1] = v2-v1
            pE[n1] = v1

        end

    end

    local intercepts = {}
    local nInt = 0

    local function cross2d(r, f)
        return FP.matL:GetForward():Dot( r:Cross(f) )
    end

    for k = 1, #vE do

        -- print(type(ph),ph)
        local denom = cross2d(ph, vE[k])

        if math.abs(denom) <= 1e-8 then continue end

        local t = cross2d(pE[k]-O, vE[k]) / denom
        local s = cross2d(pE[k]-O, ph)    / denom

        if (t >= 0) and (0 - 1e-9 <= s) and (s <= 1 + 1e-9) then
            if intercepts[1] then
                if math.abs(intercepts[1] - t) <= 1e-4 then continue end
            end
            nInt = nInt + 1
            intercepts[nInt] = t
        else
            continue
        end

    end

    if nInt == 0 then return end

    if nInt == 1 then

        return 0, intercepts[1]

    else

        return intercepts[1], intercepts[2]

    end

end

local function clippedray(FP, vI, D, vE, pE)

    local t1, t2 = parametricray(FP, vI, D, vE, pE)
    if t1 == nil then return end

    local v1 = vI + D*t1
    local v2 = vI + D*t2

    return v1, v2, t1, t2

end

local function clippedraywithending(FP, vI, D, L, vE, pE)

    local t1, t2 = parametricray(FP, vI, D, vE, pE)
    if t1 == nil then return end

    local p1 = math.min( math.max( t1 , 0 ), L)
    local p2 = math.min( t2 , L )

    -- if p2 > L then return end
    -- if t2 <= 0 then return end
    -- if p1 < p2 then return end
    -- print(p1, p2)

    local v1 = vI + D * p1
    local v2 = vI + D * p2

    return v1, v2

end

-- local function HandleGrid(FP) end

local polarpatterns = {
    { 60,  30,  15,   5,   1 },
    { 90,  30,  15,   5,   1 },
    { 90,  45,  15,   5,   1 },
    { 90 }, -- binary subdivision
    { 60,  20,  10,   2,   1 },
    { 40,   8,   4,   2,   1 },
} 

for i = 1, 12 do
    local pp = polarpatterns[4]
    pp[i+1] = pp[i]/2
end 

local grid_frameStart = 0 

local grid_targetSec

local function checkpoint()

    if (SysTime() - grid_frameStart) > grid_targetSec then
        coroutine.yield()
    end

end



local ang_buckets = 3600
local eps_ang = 2*math.pi/ang_buckets
local function keyForAng(th)
    return math.floor(th / eps_ang + 0.5) % ang_buckets
end

local function CreateGrid(FP, typ)

    local grid_targetFPS  = cNum("fpsforgridyield")
    grid_targetSec  = 1/grid_targetFPS

    local pb = FP.physicsbone

    local matW = FocusEntity.WorldMatrices[pb]

    -- local typ = polar and "polar" or "cartesian" 

    local function addline(data)
        table.insert( FP.gridBuffer[typ].pucklines , data )
    end

    -- local function addpoint(data,typ)
    --     typ = "cartesian" or typ
    --     table.insert( FP.gridBuffer[typ].focalpoints , data )
    -- end

    local u = -FP.matL:GetRight()
    local v = FP.matL:GetUp()
    local N = FP.matL:GetForward()

    local numv = #FP.vertices3D

    -- local cen = FP.centroid
    local cen = FP.mcPos

    FocusEntity.GridCenter = cen

    local vE = {}
    local pE = {}

    local furthest
    local furthestDist = 0

    local closest
    local closestDist = math.huge

    for n1=1, numv do -- outline of poly

        n2 = n1%numv+1

        local v1 = FP.vertices3D[n1]
        local v2 = FP.vertices3D[n2]

        local disp = (cen - v1)

        local dist = disp:LengthSqr()
        if furthestDist < dist then
            furthest = n1
            furthestDist = dist
        end

        vE[n1] = v2-v1
        pE[n1] = v1

        local distreal = disp:Dot( vE[n1]/vE[n1]:Length() )
        -- print(distreal < closestDist, distreal, closestDist)
        if distreal < closestDist then
            closest = n1
            closestDist = distreal
        end

        -- puckline(
        --     matW * v1, 
        --     matW * v2, 
        --     255,255,255,255, 
        --     1
        -- )

        addline( {v1, v2} )

    end

    local dI = CELLWIDTH

    local maxdist = math.sqrt(furthestDist)

    if type(FP.gridData) != "table" then FP.gridData = {} end

    -- FP.gridData = { 
    --     cartesian = { ticks = {}, rayends = {} },
    --     polar     = { ticks = {}, rayends = {} }
    -- }

    FP.gridData[typ] = { ticks = {}, rayends = {} }

    if typ=="polar" then

        local dtheta = 0 
        local ith = 0

        maxlayers = math.min( furthestDist/dI, 256 )
        local maxl = maxdist/dI

        local P = polarpatterns[4] -- 90,  45,  15,   5,   1, 0.5

        local maxsubdiv = 128
        -- local ith = (1/cartes) * math.pi
        local lines = 360 / P[1]

        local ith = 0

        local dist

        local targetArea = (math.pi*dI^2)/lines

        -- print(FP.area)

        local drawnAngles = {}

        local n = 1

        local hashit = false

        for l = 1, math.ceil(maxlayers) do

            -- print("LAYAR:",l)

            local nohits = true

            dist = dI * (l-1)

            if dist >= furthestDist then break end

            local reversealpha = false
            local alpha = reversealpha and dist/maxdist or 1-dist/maxdist
            if reversealpha then alpha = (1+9*alpha)/10 end

            dtheta = 2*math.pi/lines

            if P[n+1] then 

                for i = 1, lines do -- polar rays

                    local th = ith + dtheta*(i-1)
                    th = th%(2*math.pi)

                    if drawnAngles[keyForAng(th)] then continue end

                    drawnAngles[keyForAng(th)] = true

                    -- local th = ith
                    -- print(ith, dtheta*(i-1), ith + dtheta*(i-1))
                    local ph = (u*math.cos(th) + v*math.sin(th))
                    local O = cen + ph*dist

                    -- print(i,"/",lines)

                    local v1, v2 = clippedray(FP, O, ph, vE, pE)

                    if v1 == nil then continue else 
                        nohits = false 
                        hashit = true
                    end 

                    local ray = (v2-v1)

                    local raylen = ray:Length()

                    local raydir = ray/raylen

                    for j = 0, math.floor(raylen/dI) do

                        local tickpos = v1 + dI*raydir*j

                        FP.gridData[typ].ticks[keyForPos(tickpos)] = tickpos

                    end

                    FP.gridData[typ].rayends[keyForPos(v2)] = v2

                    -- table.insert(FocusEntity.Grid.focalpoints)

                    -- addline( {v1 - N*l*3, v2 - N*l*3, nil,nil,nil,255*alpha,((l == 1) and 2 or 1)} )
                    -- addline( {v1 + N*i, v2 + N*i, nil,nil,nil,255*alpha,((l == 1) and 2 or 1)} )
                    addline( {v1, v2, nil,nil,nil,255*alpha,((l == 1) and 2 or 1)} )

                end

                local lnext = lines * ( P[n]/P[n+1] )

                local Anext = 1/lnext * math.pi * ((2*dI+dist)^2 - (dI+dist)^2)

                local doprog = (Anext >= targetArea)

                if doprog then

                    lines = lnext
                    ith   = ith + 2*math.pi / lines

                    n = n + 1

                end

            end

            local minsides = 16
            local maxsides = 32
            -- local sides = math.max(minsides,lines*2)
            -- local sides = math.Clamp(lines,minsides,maxsides)
            local sides = lines

            if sides < minsides then
                local quo = math.ceil(minsides/sides)
                sides = sides * quo
            end
                sides = math.min(sides,maxsides)

            local dtheta2 = 1/sides * 2*math.pi
            local len = 2 * dist * math.sin(dtheta2/2)

            for j = 1, sides do -- circle contours

                if l == 1 then continue end

                local th = ((j-1)/sides) * 2*math.pi
                local thdir = th + math.pi * (1/2 + 1/sides)
                local ph = (u*math.cos(th) + v*math.sin(th))
                local dir = (u*math.cos(thdir) + v*math.sin(thdir))
                local org = cen + ph * dist

                v1, v2 = clippedraywithending(FP, org, dir, len, vE, pE)
                if v1 == nil then continue else 
                    nohits = false
                    hashit = true 
                end

                local thickness = 1

                local a2 = alpha * ( ( l==2 or (l-1)%4==0 ) and 1 or 0.25 ) 

                addline( {v1, v2, nil,nil,nil,255*a2,thickness} )

                if sides % 8 == 0 then checkpoint() end
                
            end

            if nohits and hashit then break end

            checkpoint()

        end

    else -- cartesian

        -- print("cartesian:",maxdist,dI, pE)
        -- PrintTable(pE)

        -- dI = 1

        local org = cen -(v)*maxdist

        local dir_ray = v
        local dir_ptr = u

        local alpha = 255

        for _ = 1, 2 do 

            local i = 0

            local hashit = false
            local nohits = true

            for i0 = 0, 2*(maxdist-1)/dI, 1 do

                i = i + i0*(-1)^i0
                -- print(i, i0*(-1)^i0)

                local thickness = (i == 0) and 2 or 1

                print(i)

                local O = org+i*dir_ptr*dI

                v1, v2, t1, t2 = clippedray(FP, 
                    O, 
                    dir_ray, 
                vE, pE)

                if v1 == nil then 
                    nohits = true 
                    continue
                else
                    nohits = false
                    hashit = true
                end

                if nohits and hashit then break end

                -- v1 = org+i*dI*dir_ptr

                -- v2 = v1+dir_ray*maxdist*2

                alpha = i==0 and 1 or math.Clamp( i0*dI/maxdist , 0.1, 1)
                alpha = alpha * ( (i%4 != 0) and 0.25 or 1)

                addline( {v1, v2, nil,nil,nil,255 * alpha, thickness } )

                FP.gridData[typ].rayends[keyForPos(v1)] = v1
                FP.gridData[typ].rayends[keyForPos(v2)] = v2

                -- local dist = (v2-v1):Length()
                local dist = t2-t1
                -- local dist = (v2-v1):Dot(dir_ptr)

                local d = math.floor(dist)
                d = 1

                if _ == 1 then

                    if t2-t1 < 0 then 
                        local t3 = t2
                        t2 = t1
                        t1 = t3
                    end 

                    local d_est1 = math.ceil((t1-maxdist)/dI)*dI
                    local d_est2 = math.floor((t2-maxdist)/dI)*dI

                    -- print("=============================")
                    -- print("1:",t1,"d_est:",d_est1,"t:",t1,"t-md:",t1-maxdist,"(t-md)/dI:",(t1-maxdist)/dI)
                    -- print("2:",t2,"d_est:",d_est2,"t:",t2,"t-md:",t2+maxdist,"(t-md)/dI:",(t2-maxdist)/dI)

                    n1 = d_est1 + maxdist
                    n2 = d_est2 + maxdist

                    if n2 < n1 then continue end

                    local p1 = O + n1*dir_ray
                    local p2 = O + n2*dir_ray

                    for a0 = n1, n2, dI do

                        -- local tickpos = cen + math.floor(a0 - math.floor(d) + dist/2 + 1)*dI * dir_ray + i*dI * dir_ptr
                        local tickpos = O + a0*dir_ray

                        -- addline( {p1, p2+N, nil,nil,255,255 * alpha, thickness } )
                        -- keyForPos(tickpos)

                        FP.gridData[typ].ticks[keyForPos(tickpos)] = tickpos

                        -- addline( {tickpos, tickpos+N, nil,nil,255,255 * alpha, thickness } )

                    end

                end

                -- thickness = 1

                checkpoint()

            end

            dir_ray = u
            dir_ptr = v
            org = cen -(u)*maxdist*dI

        end

    end

    BuildGridIndex(FP.gridData[typ])

end

local function DrawGrid(FP, typ)

    local pb = FP.physicsbone

    local matW = FocusEntity.WorldMatrices[pb]
    local matWNT = FocusEntity.WorldMatricesNoTR[pb]

    local dot = (-EyeVector():Dot( matWNT * ( FP.matL:GetForward() ) ) )
    local facing = dot > 0

    local alphamul = math.abs(dot)

    for i,data in pairs(FP.gridBuffer[typ].pucklines) do

        puckline(
            matW * data[1],
            matW * data[2],
            facing and ( data[3] or 255 ) or 255,
            facing and ( data[4] or 255 ) or 64 + 64 * 0.5 * (1+math.sin(3*CurTime())),
            facing and ( data[5] or 255 ) or 64,
            -- ( data[6] or 255 )* math.Clamp(CurTime()-FP.bufferTime,0,1),
            (data[6] or 255) * alphamul ,
            -- data[6] or 255,
            data[7] or 1
        )

    end

end

local cwprev

local function HandleGrid(FP)

    CELLWIDTH = cNum("cellwidth")
    if cwprev != CELLWIDTH then FP.gridBuffer = nil end
    cwprev = CELLWIDTH

    grid_frameStart = SysTime()

    local typ = ALTING and "polar" or "cartesian"
    -- print("typ:",typ)

    if type(FP.gridBuffer) != "table" then
    -- if true then

        FP.gridBuffer = { 
            polar = {
                pucklines = {},
                co = coroutine.create(CreateGrid)
            }, 
            cartesian = {
                pucklines = {},
                co = coroutine.create(CreateGrid)
            } 
        }
        -- FP.bufferTime = CurTime()
        -- FP.gridCo = coroutine.create(CreateGrid)
        -- FP.gridCoStarted = false

    end

    local co = FP.gridBuffer[typ].co

    if co then
        if ( coroutine.status(co) == "dead" ) then
            co = nil
        else
            local didnoterror, err = coroutine.resume(co, FP,typ)
            if !didnoterror then 
                co = nil
                ErrorNoHalt("[pucksnap2] coroutine error for grid handling: ",err)
            -- elseif ( coroutine.status(co) == "dead" ) then
            --     co = nil
            end
        end
    end 

    -- CreateGrid(FP)
    DrawGrid(FP, typ)

end


local function HandleGrid2(FP)

    local pb = FP.physicsbone

    local matW = FocusEntity.WorldMatrices[pb]

    numv = #FP.vertices3D

    local FPV = {}
    for k,v in pairs(FP.vertices3D) do FPV[k] = v end

    -- local FPV_ = table.Copy(FPV)

    local FPO = {}
    for k,v in pairs(FP.offsets3D) do FPO[k] = v end

    local FPN = {}
    for k,v in pairs(FP.normals3D) do FPN[k] = v end

    local FPS = {} -- stacked offset vector
    for k,v in pairs(FP.normals3D) do FPS[k] = Vector() end
    local FPC = {} -- clipped offset value
    for k,v in pairs(FP.normals3D) do FPC[k] = 0 end

    -- ::meow::

    local insets = 4
    local insetwidth = TimedCos(0.5, 1, 2, 0)

    -- FPV[3] = nil
    -- FPV[4] = nil

    for p = 0, insets do

        local iw = p * insetwidth

        local num = #FPV

        -- PrintTable(FPO)
        -- for i = 1, num do
        local i = 1
        while i != #FPV do

            if #FPV <= 2 then break end

            local n0 = (i-2)%#FPV+1
            local n1 = i
            local n2 = i%#FPV+1

            -- print("ECW: ", FPV[n1], FPV[n2], FPO[n1], FPO[n2])
            local cw = EdgeCollapseWidth( FPV[n1], FPV[n2], FPO[n1], FPO[n2] )

            local clpse = iw > cw

            if clpse then 
                local N0, N2 = FPN[n0], FPN[n2]
                if type(N0) != "Vector" then return end
                FPS[n1] = FPO[n1] * iw
                FPC[n1] = -iw
                FPO[n1] = ( N0 + N2 ) / ( 1 + N0:Dot(N2) )

                -- print("1:", FPV[n2])

                table.remove(FPV, n2)
                table.remove(FPS, n2)
                table.remove(FPN, n1)
                table.remove(FPC, n2)
                table.remove(FPO, n2)
                -- PrintTable(FPO)

                -- print("2:", FPV[n2])
            else
                i = i + 1
            end

            if i >= #FPV then break end

        end

        num = #FPV

        for i = 1, num do

            local n1 = i
            local n2 = i%num+1

            -- local V1 = FPV[n1] + (iw+FPC[n1]) * FPO[n1] + FPS[n1]
            -- local V2 = FPV[n2] + (iw+FPC[n2]) * FPO[n2] + FPS[n2]

            local V1 = FPV[n1]
            local V2 = FPV[n2]

            -- if (FPC[n1] != 0) or (FPC[n2] != 0) then

            --     local V1 = FPV[n1] + (iw+FPC[n1]) * FPO[n1]
            --     local V2 = FPV[n2] + (iw+FPC[n2]) * FPO[n2]

            -- end

            -- local V1 = FPV[n1] + (iw+FPC[n1]) * FPO[n1]
            -- local V2 = FPV[n2] + (iw+FPC[n2]) * FPO[n2]

            puckline( 
                matW * V1, 
                matW * V2, 
                255,255,255,255, 
                -- dbc.r,dbc.g,dbc.b,alpha, 
                thickness or 1
            )

        end

    end

    -- for i = 1, numv do

    --     -- insetwidth = insetwidth + 0.01
    --     local dbc = HSVToColor(i/numv*360, 1, 1) --debug color

    --     if FPV[i] == nil then continue end

    --     local n1 = i
    --     local n2

    --     for j = 0, numv do
    --         local check = (j+i)%numv+1
    --         -- print(check, FPV[check])
    --         if FPV[check] != nil then
    --             n2 = check
    --             break
    --         end
    --     end

    --     if n2 == nil then return end

    --     local v1, v2 = FPV[n1], FPV[n2]
    --     local o1, o2 = FPO[n1], FPO[n2]

    --     -- ||/// handle miter offset collapse /////////||

    --     local collapsewidth

    --     local E0 = v2-v1
    --     local D  = o2-o1
    --     local DD = D:Dot(D)

    --     if DD < 1e-8 then 
    --         collapsewidth = math.huge
    --     end

    --     local collapsewidth = -(E0:Dot(D)) / DD
    --     -- print(i, t)

    --     -- ||/// eyuuup ///////////////////////////////||

    --     local thickness = 2

    --     for p = 0, insets do

    --         local iw = p * insetwidth

    --         local vo1 = v1 + o1
    --         local vo2 = v2 + o2

    --         -- if iw > collapsewidth then
    --         --     collapsewidth*(vo1 + vo2)
    --         -- end

    --         local V1 = v1 + o1 * iw
    --         local V2 = v2 + o2 * iw

    --         puckline( 
    --             matW * V1, 
    --             matW * V2, 
    --             -- 255,255,255,alpha, 
    --             dbc.r,dbc.g,dbc.b,alpha, 
    --             thickness 
    --         )

    --         thickness = 1

    --     end

    -- end

end

hook.Remove("HUDPaint", PS_.."2ddraw")
hook.Add("HUDPaint", PS_.."2ddraw", function()

    if !ENABLED then return end

    -- if !FocusEntity.Locked then
        if !FocusEntity.PrepFrame() then return end
    -- end
    if !FocusEntity.HasFrameBeenPrepped() then return end

    if FocusEntity.Entity != FocusEntity.tr.Entity then return end

    local pb = FocusEntity.tr.PhysicsBone + 1

    local FP = FocusEntity.FocusPolygon

    for bone_ind, B in pairs(FocusEntity.PerBone) do

        local curbone = bone_ind == pb

        DrawWorldSpaceAABB(bone_ind,255,150,150,50,true)
        DrawWorldSpaceAABB(bone_ind,255,0,0,50)
        SmartSnapianBoneAABB(bone_ind, 0,0,255,curbone and 200 or 20)

        if !curbone then continue end

        local monoconvex = B.ConvexCount == 1

        local matW = FocusEntity.WorldMatrices[pb]

        local matWnoTR = FocusEntity.WorldMatricesNoTR[pb]

        -- print(Wmat, FocusEntity.WorldMatrices, pb, FocusEntity.WorldMatrices[1])

        for convex_ind, C in pairs(B.PerConvex) do

            local curconvex = FocusConvex() == convex_ind
            -- if !curconvex then

            -- if cBool("masscenterproj") then

            --     for k_detN, poly in pairs(C.polygons) do

            --         if not poly.mcWithin then continue end
            --         if poly == FP then continue end

            --         pucksprite( matW * poly.mcPos, cIcon("masscenter"), 16, 100,100,255,100 )

            --     end

            -- end

            -- end

            -- if !curconvex then continue end

            for k_edge, edge in pairs(C.edges) do

                local curpoly = false

                local polys = {}

                local facingct = 0

                for k_detN, bool in pairs(edge.normals) do

                    local poly = C.polygons[k_detN]

                    polys[#polys+1] = poly

                    if poly == FP then curpoly = true end

                    local pmatW = matW * C.polygons[k_detN].matL

                    if ( EyePos() - pmatW:GetTranslation() ):Dot(pmatW:GetForward()) > 0 then
                        facingct = facingct + 1
                    end

                end

                if facingct == 0 then continue end

                if curpoly and ISLOCKABLE then continue end

                local outeredge = facingct==1

                -- local alpha = 255 * cNum("lineopacity") * ( curpoly and 1 or ( monoconvex and 0.1 or 0.5 ) ) * ( curconvex and 1 or 0.5 )

                local alpha = 255 * cNum("lineopacity") * ( monoconvex and 0.1 or 0.5 ) * ( curconvex and 1 or 0.5 )

                -- if curpoly then continue end

                local thickness = ( facingct==1 and !curconvex ) and 2 or 1
                local r,g,b = 255,255,255

                -- if ( outeredge and !curconvex ) then 
                if !curconvex then 
                    r,g,b = 100,100,255
                end

                puckline( matW * edge.v1, matW * edge.v2, r,g,b,alpha, thickness )

            end

        end

        if !curbone then continue end

        if ISLOCKABLE then HandleGrid(FP) end

        FoPt = FocusEntity.Grid.focalpoint

        if type(FoPt) != "table" then return end

        local posW = matW * FoPt.pos

        if (cBool("fponlywhenlockable") and ISLOCKABLE) or !cBool("fponlywhenlockable") then

            pucksprite( posW, cIcon(FoPt.type, FocusEntity.Locked and "selected"), 16 )

        end

        local tr = LocalPlayer():GetEyeTrace()
        local hp = tr.HitPos

        cam.Start3D()

            if ISLOCKABLE then arrowAB( hp, posW, 0.5, 1, Color(0,0,255,50) ) end
            -- print((hp-posW):Length())

            local col = (FocusEntity == tr.Entity) and Color(0, 255, 0, 50) or Color(255, 0, 0, 100)

            if cBool("drawhitnormals") then

                arrow( hp, tr.HitNormal, 16, col, 1, true )

            end

        cam.End3D()

        -- local mc = FocusEntity.MassCenters[pb]

        -- local mcP = mc + (FP.matL:GetTranslation()-mc):Dot(FP.matL:GetForward()) * FP.matL:GetForward()

        -- pucksprite( matW * (FP.mcWithin and FP.mcPos or FP.mcDisp), cIcon("masscenter"), 16 )

        -- print(FocusEntity.Locked)
 
    end

    -- drawpucklines()

end)

local patchcuke = {"LeftClick", "RightClick"}
local oldinstances = {} -- { toolname = { LeftClick = functionthis, RightClick = functionthat, ... } ... } 

local function patchtooltraces()

    tool = LocalPlayer():GetTool()

    if tool == nil then return end
    -- print("oooog")

    local tr = FocusEntity.tr

    -- print(tr.HitPos, FocusEntity.Grid.focalpoint.posW)

    if tr.Entity:GetModel() != string.lower("models/props_junk/MetalBucket02a.mdl") then return end

    local wep = LocalPlayer():GetActiveWeapon()

    if !IsValid( wep ) or wep:GetClass() != "gmod_tool" then return end

    local mode = wep:GetMode()

    if type(oldinstances[mode]) != "table" then oldinstances[mode] = {} end

    for _, nom in pairs(patchcuke) do

        if type(oldinstances[mode][nom]) == "table" then continue end 

        oldinstances[mode][nom] = tool[nom]

        tool[nom] = function( self, tr )
            return oldinstances[mode][nom]( self, tr )
        end

        local hstr = PS_.."resettool_"..mode.."_for_"..nom

        hook.Add("Think", hstr, function()

            if FocusEntity.Locked then return end

            tool[nom] = oldinstances[mode][nom]

            hook.Remove("Think", hstr)

        end)

    end

end

local function isnan(n) return n~=n end
local function isinf(n) return (n==math.huge) or (n==-math.huge) end
local function wackangle(A)
    if  isnan(A.p) or isinf(A.p) or
        isnan(A.y) or isinf(A.y) or
        isnan(A.r) or isinf(A.r) then
        return true
    else
        return false
    end
end

hook.Remove("CalcView", PS_.."whippersnapper")
hook.Remove("CreateMove", PS_.."whippersnapper")
local oldang
local wasdt0
local angv = Angle()
local justLocked = false
hook.Add("CreateMove", PS_.."whippersnapper", function(user)

    if (type(FocusEntity.Grid) != "table") or (type(FocusEntity.Grid.focalpoint) != "table") then 
        oldang = 0
        return 
    end

    -- print(FocusEntity.tr.HitPos)

    justLocked = true
    if !FocusEntity.Locked then return end

    -- patchtooltraces(LocalPlayer():GetTool())

    local fp = FocusEntity.Grid.focalpoint
    local ang = ( FocusEntity.WorldMatrix * fp.pos + (FocusEntity.tr.HitNormal * DIST_EPSILON * 1 ) - EyePos() ):Angle()

    local tf = CurTime()
    local dt = ti and (tf - ti) or FrameTime()
    local dt0 = dt == 0

    local setang = ang
    if type(oldang) == "Angle" then
        if !(dt0 or wasdt0) then
            angv = (ang-oldang)/dt
        end
        if wackangle(angv) then angv = Angle() end -- fix NaN
        setang = justLocked and ang or ang + angv * -100
    end 

    oldang = ang
    ti = tf
    wasdt0 = dt0
    justLocked = false

    user:SetViewAngles(setang)

end)


hook.Remove("CreateMove", PS_.."whippersnapper")
hook.Remove("CreateMove", PS_.."whippersnapper2")
hook.Add("CreateMove", PS_.."whippersnapper2", function(user)

    if (type(FocusEntity.Grid) != "table") or (type(FocusEntity.Grid.focalpoint) != "table") then return end

    if !FocusEntity.Locked then return end

    user:SetViewAngles( ( FocusEntity.WorldMatrix * FocusEntity.Grid.focalpoint.pos + (FocusEntity.tr.HitNormal * DIST_EPSILON * 1 ) - EyePos() ):Angle() )

end)



