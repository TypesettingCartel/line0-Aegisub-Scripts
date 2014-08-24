local re = require("aegisub.re")
local util = require("aegisub.util")
local l0Common = require("l0.Common")

function createASSClass(typeName,baseClass,order,types,tagProps)
  local cls, baseClass = {}, baseClass or {}
  for key, val in pairs(baseClass) do
    cls[key] = val
  end

  cls.__index = cls
  cls.instanceOf = {[cls] = true}
  cls.typeName = typeName
  cls.__meta__ = { 
       order = order,
       types = types
  }
  cls.__defProps = table.merge(cls.__defProps or {},tagProps or {})
  cls.baseClass=baseClass

  setmetatable(cls, {
    __call = function (cls, ...)
        local self = setmetatable({__tag = util.copy(cls.__defProps)}, cls)
        self = self:new(...)
        return self
    end})
  return cls
end

ASSBase = createASSClass("ASSBase")
function ASSBase:checkType(type_, ...) --TODO: get rid of
    for _,val in ipairs({...}) do
        result = (type_=="integer" and math.isInt(val)) or type(val)==type_
        assert(result, string.format("Error: %s must be a %s, got %s.\n",self.typeName,type_,type(val)))
    end
end

function ASSBase:checkPositive(...)
    self:checkType("number",...)
    for _,val in ipairs({...}) do
        assert(val >= 0, string.format("Error: %s tagProps do not permit numbers < 0, got %d.\n", self.typeName,val))
    end
end

function ASSBase:checkRange(min,max,...)
    self:checkType("number",...)
    for _,val in ipairs({...}) do
        assert(val >= min and val <= max, string.format("Error: %s must be in range %d-%d, got %d.\n",self.typeName,min,max,val))
    end
end

function ASSBase:CoerceNumber(num, default)
    num = tonumber(num)
    if not num then num=default or 0 end
    if self.__tag.positive then num=math.max(num,0) end
    if self.__tag.range then num=util.clamp(num,self.__tag.range[1], self.__tag.range[2]) end
    return num 
end

function ASSBase:getArgs(args, default, coerce, ...)
    assert(type(args)=="table", "Error: first argument to getArgs must be a table of packed arguments, got " .. type(args) ..".\n")
    -- check if first arg is a compatible ASSTag and dump into args 
    if #args == 1 and type(args[1]) == "table" and args[1].typeName then
        local res, selfClasses = false, {}
        for key,val in pairs(self.instanceOf) do
            if val then table.insert(selfClasses,key) end
        end
        for _,class in ipairs(table.join(table.pack(...),selfClasses)) do
            res = args[1].instanceOf[class] and true or res
        end
        assert(res, string.format("%s does not accept instances of class %s as argument.\n", self.typeName, args[1].typeName))
        args=table.pack(args[1]:get())
    end

    local valTypes, j, outArgs = self.__meta__.types, 1, {}
    for i,valName in ipairs(self.__meta__.order) do
        -- write defaults
        args[j] = type(args[j])=="nil" and default or args[j]

        if type(valTypes[i])=="table" and valTypes[i].instanceOf then
            local subCnt = #valTypes[i].__meta__.order
            outArgs = table.join(outArgs, {valTypes[i]:getArgs(table.sliceArray(args,j,j+subCnt-1), default, coerce)})
            j=j+subCnt-1

        elseif coerce then
            local tagProps = self.__tag or self.__defProps
            local map = {
                number = function() return tonumber(args[j],tagProps.base or 10)*(tagProps.scale or 1) end,
                string = function() return tostring(args[j]) end,
                boolean = function() return not (args[j] == 0 or not args[j]) end
            }
            table.insert(outArgs, args[j]~= nil and map[valTypes[i]]() or nil)
        else table.insert(outArgs, args[j]) end
        j=j+1
    end
    --self:typeCheck(unpack(outArgs))
    return unpack(outArgs)
end

function ASSBase:typeCheck(...)
    local valTypes, j, args = self.__meta__.types, 1, {...}
    --assert(#valNames >= #args, string.format("Error: too many arguments. Expected %d, got %d.\n",#valNames,#args))
    for i,valName in ipairs(self.__meta__.order) do
        if type(valTypes[i])=="table" and valTypes[i].instanceOf then
            if type(args[j])=="table" and args[j].instanceOf then
                self[valName]:typeCheck(args[j])
                j=j+1
            else
                local subCnt = #valTypes[i].__meta__.order
                valTypes[i]:typeCheck(unpack(table.sliceArray(args,j,j+subCnt-1)))
                j=j+subCnt
            end
        else    
            assert(type(args[i])==valTypes[i] or type(args[i])=="nil" or valTypes[i]=="nil",
                   string.format("Error: bad type for argument %d (%s). Expected %s, got %s.\n", i,valName,type(self[valName]),type(args[i]))) 
        end
    end
end

function ASSBase:get()
    local vals = {}
    for _,valName in ipairs(self.__meta__.order) do
        if type(self[valName])=="table" and self[valName].instanceOf then
            for _,cval in pairs({self[valName]:get()}) do vals[#vals+1]=cval end
        else 
            vals[#vals+1] = self[valName]
        end
    end
    return unpack(vals)
end

function ASSBase:commonOp(method, callback, default, ...)
    local args = {self:getArgs({...}, default, false)}
    local j, res = 1, {}
    for _,valName in ipairs(self.__meta__.order) do
        if type(self[valName])=="table" and self[valName].instanceOf then
            local subCnt = #self[valName].__meta__.order
            res=table.join(res,{self[valName][method](self[valName],unpack(table.sliceArray(args,j,j+subCnt-1)))})
            j=j+subCnt
        else 
            self[valName]=callback(self[valName],args[j])
            j=j+1
            table.insert(res,self[valName])
        end
    end
    return unpack(res)
end

function ASSBase:add(...)
    return self:commonOp("add", function(a,b) return a+b end, 0, ...)
end

function ASSBase:mul(...)
    return self:commonOp("mul", function(a,b) return a*b end, 1, ...)
end

function ASSBase:pow(...)
    return self:commonOp("pow", function(a,b) return a^b end, 1, ...)
end

function ASSBase:set(...)
    return self:commonOp("set", function(a,b) return b end, nil, ...)
end

function ASSBase:mod(callback, ...)
    return self:set(callback(self:get(...)))
end

function ASSBase:readProps(tagProps)
    for key, val in pairs(tagProps or {}) do
        self.__tag[key] = val
    end
end


ASSNumber = createASSClass("ASSNumber", ASSBase, {"value"}, {"number"}, {base=10, precision=3, scale=1})

function ASSNumber:new(val, tagProps)
    self:readProps(tagProps)
    self.value = type(val)=="table" and self:getArgs(val,0,true) or val or 0
    self:typeCheck(self.value)
    if self.__tag.positive then self:checkPositive(self.value) end
    if self.__tag.range then self:checkRange(self.__tag.range[1], self.__tag.range[2], self.value) end
    return self
end

function ASSNumber:getTag(coerce, precision)
    self:readProps(tagProps)
    precision = precision or self.__tag.precision
    local val = self.value
    if coerce then
        self:CoerceNumber(val,0)
    else
        assert(precision <= self.__tag.precision, string.format("Error: output wih precision %d is not supported for %s (maximum: %d).\n", 
               precision,self.typeName,self.__tag.precision))
        self:typeCheck(self.value)
        if self.__tag.positive then self:checkPositive(val) end
        if self.__tag.range then self:checkRange(self.__tag.range[1], self.__tag.range[2],val) end
    end
    return math.round(val,self.__tag.precision)
end


ASSPosition = createASSClass("ASSPosition", ASSBase, {"x","y"}, {"number", "number"})
function ASSPosition:new(valx, valy, tagProps)
    if type(valx) == "table" then
        tagProps = valy
        valx, valy = self:getArgs(valx,0,true)
    end
    self:readProps(tagProps)
    self:typeCheck(valx, valy)
    self.x, self.y = valx, valy
    return self
end


function ASSPosition:getTag(coerce, precision)
    local x,y = self.x, self.y
    if coerce then
        x,y = self:CoerceNumber(x,0), self:CoerceNumber(y,0)
    else 
        self:checkType("number", x, y)
    end
    precision = precision or 3
    local x = math.round(x,precision)
    local y = math.round(y,precision)
    return x,y
end
-- TODO: ASSPosition:move(ASSPosition) -> return \move tag

ASSTime = createASSClass("ASSTime", ASSNumber, {"value"}, {"number"}, {precision=0})
-- TODO: implement adding by framecount

function ASSTime:getTag(coerce, precision)
    precision = precision or 0
    local val = self.value
    if coerce then
        precision = math.min(precision,0)
        val = self:CoerceNumber(0)
    else
        assert(precision <= 0, "Error: " .. self.typeName .." doesn't support floating point precision")
        self:checkType("number", self.value)
        if self.__tag.positive then self:checkPositive(self.value) end
    end
    val = val/self.__tag.scale
    return math.round(val,precision)
end

ASSDuration = createASSClass("ASSDuration", ASSTime, {"value"}, {"number"}, {positive=true})
ASSHex = createASSClass("ASSHex", ASSNumber, {"value"}, {"number"}, {range={0,255}, base=16, precision=0})

ASSColor = createASSClass("ASSColor", ASSBase, {"r","g","b"}, {ASSHex,ASSHex,ASSHex})   
function ASSColor:new(r,g,b, tagProps)
    if type(r) == "table" then
        tagProps = g
        r,g,b = self:getArgs({r[1]:match("(%x%x)(%x%x)(%x%x)")},0,true)
    end 
    self:readProps(tagProps)
    self.r, self.g, self.b = ASSHex(r), ASSHex(g), ASSHex(b)
    return self
end

function ASSColor:addHSV(h,s,v)
    local ho,so,vo = util.RGB_to_HSV(self.r:get(),self.g:get(),self.b:get())
    local r,g,b = util.HSV_to_RGB(ho+h,util.clamp(so+s,0,1),util.clamp(vo+v,0,1))
    return self:set(r,g,b)
end

function ASSColor:getTag(coerce)
    return self.b:getTag(coerce), self.g:getTag(coerce), self.r:getTag(coerce)
end

ASSFade = createASSClass("ASSFade", ASSBase,
    {"startDuration", "endDuration", "startTime", "endTime", "startAlpha", "midAlpha", "endAlpha"},
    {ASSDuration,ASSDuration,ASSTime,ASSTime,ASSHex,ASSHex,ASSHex}
)
function ASSFade:new(startDuration,endDuration,startTime,endTime,startAlpha,midAlpha,endAlpha,tagProps)
    if type(startDuration) == "table" then
        tagProps = endDuration or {}
        prms={self:getArgs(startDuration,nil,true)}
        if #prms == 2 then 
            startDuration, endDuration = unpack(prms)
            tagProps.simple = true
        elseif #prms == 7 then
            startDuration, endDuration, startTime, endTime = prms[5]-prms[4], prms[7]-prms[6], prms[4], prms[7] 
        end
    end 
    self:readProps(tagProps)

    self.startDuration, self.endDuration = ASSDuration(startDuration), ASSDuration(endDuration)
    self.startTime = self.__tag.simple and ASSTime(0) or ASSTime(startTime)
    self.endTime = self.__tag.simple and nil or ASSTime(endTime)
    self.startAlpha = self.__tag.simple and ASSHex(0) or ASSHex(startAlpha)
    self.midAlpha = self.__tag.simple and ASSHex(255) or ASSHex(midAlpha)
    self.endAlpha = self.__tag.simple and ASSHex(0) or ASSHex(endAlpha)
    return self
end

function ASSFade:getTag(coerce)
    if self.__tag.simple then
        return self.startDuration:getTag(coerce), self.endDuration:getTag(coerce)
    else
        local t1, t4 = self.startTime:getTag(coerce), self.endTime:getTag(coerce)
        local t2 = t1 + self.startDuration:getTag(coerce)
        local t3 = t4 - self.endDuration:getTag(coerce)
        if not coerce then
             self:checkPositive(t2,t3)
             assert(t1<=t2 and t2<=t3 and t3<=t4, string.format("Error: fade times must evaluate to t1<=t2<=t3<=t4, got %d<=%d<=%d<=%d", t1,t2,t3,t4))
        end
        return self.startAlpha, self.midAlpha, self.endAlpha, math.min(t1,t2), util.clamp(t2,t1,t3), math.clamp(t3,t2,t4), math.max(t4,t3) 
    end
end

ASSMove = createASSClass("ASSMove", ASSBase,
    {"startPos", "endPos", "startTime", "endTime"},
    {ASSPosition,ASSPosition,ASSTime,ASSTime}
)
function ASSMove:new(startPosX,startPosY,endPosX,endPosY,startTime,endTime,tagProps)
    if type(startPosX) == "table" then
        tagProps = startPosY
        startPosX,startPosY,endPosX,endPosY,startTime,endTime = self:getArgs(startPosX, nil, true)
    end
    self:readProps(tagProps)
    assert((startTime==endTime and self.__tag.simple~=false) or (startTime and endTime), "Error: creating a complex move requires both start and end time.\n")
    
    if startTime==nil or endTime==nil or (startTime==0 and endTime==0) then
        self.__tag.simple = true
        self.__tag.name = "moveSmpl"
    else self.__tag.simple = false end

    self.startPos = ASSPosition(startPosX,startPosY)
    self.endPos = ASSPosition(endPosX,endPosY)
    self.startTime = ASSTime(startTime)
    self.endTime = ASSTime(endTime)
    return self
end

function ASSMove:getTag(coerce)
    if self.__tag.simple or self.__tag.name=="moveSmpl" then
        return returnAll({self.startPos:getTag(coerce)}, {self.endPos:getTag(coerce)})
    else
        if not coerce then
             assert(startTime<=endTime, string.format("Error: move times must evaluate to t1<=t2, got %d<=%d.\n", startTime,endTime))
        end
        local t1,t2 = self.startTime:getTag(coerce), self.endTime:getTag(coerce)
        return returnAll({self.startPos:getTag(coerce)}, {self.endPos:getTag(coerce)},
               {math.min(t1,t2)}, {math.max(t2,t1)}) 
    end
end

ASSToggle = createASSClass("ASSToggle", ASSBase, {"value"}, {"boolean"})
function ASSToggle:new(val, tagProps)
    self:readProps(tagProps)
    if type(val) == "table" then
        self.value = self:getArgs(val,false,true)
    else 
        self.value = val or false 
    end
    self:typeCheck(self.value)
    return self
end

function ASSToggle:toggle(state)
    assert(type(state)=="boolean" or type(state)=="nil", "Error: state argument to toggle must be true, false or nil.\n")
    self.value = state==nil and not self.value or state
    return self.value
end

function ASSToggle:getTag(coerce)
    if not coerce then self:typeCheck(self.value) end
    return self.value and 1 or 0
end

ASSIndexed = createASSClass("ASSIndexed", ASSNumber, {"value"}, {"number"}, {precision=0, positive=true})
function ASSIndexed:cycle(down)
    local min, max = self.__tag.range[1], self.__tag.range[2]
    if down then
        return self.value<=min and self:set(max) or self:add(-1)
    else
        return self.value>=max and self:set(min) or self:add(1)
    end
end

ASSAlign = createASSClass("ASSAlign", ASSIndexed, {"value"}, {"number"}, {range={1,9}, default=5})

function ASSAlign:up()
    if self.value<7 then return self:add(3)
    else return false end
end

function ASSAlign:down()
    if self.value>3 then return self:add(-3)
    else return false end
end

function ASSAlign:left()
    if self.value%3~=1 then return self:add(-1)
    else return false end
end

function ASSAlign:right()
    if self.value%3~=0 then return self:add(1)
    else return false end
end

ASSWeight = createASSClass("ASSWeight", ASSBase, {"weightClass","bold"}, {ASSNumber,ASSToggle})
function ASSWeight:new(val, tagProps)
    if type(val) == "table" then
        local val = self:getArgs(val,0,true)
        self.bold = (val==1 and true) or (val==0 and false)
        self.weightClass = val>1 and true or 0
    elseif type(val) == "boolean" then
        self.bold, self.weightClass = val, 0
    else self.weightClass = val
    end
    self:readProps(tagProps)
    self.bold = ASSToggle(self.bold)
    self.weightClass = ASSNumber(self.weightClass,{positive=true,precision=0})
    return self
end

function ASSWeight:getTag(coerce)
    if self.weightClass.value >0 then
        return self.weightClass:getTag(coerce)
    else
        return self.bold:getTag(coerce)
    end
end

function ASSWeight:setBold(state)
    self.bold:set(type(state)=="nil" and true or state)
    self.weightClass.value = 0
end

function ASSWeight:toggleBold()
    self.bold:toggle()
end

function ASSWeight:setWeight(weightClass)
    self.bold:set(false)
    self.weightClass:set(weightClass or 400)
end

ASSWrapStyle = createASSClass("ASSWrapStyle", ASSIndexed, {"value"}, {"number"}, {range={0,3}, default=0})

ASSString = createASSClass("ASSString", ASSBase, {"value"}, {"string"})
function ASSString:new(val, tagProps)
    self:readProps(tagProps)
    if type(val) == "table" then
        self.value = self:getArgs(val,"",true)
    else 
        self.value = val or ""
    end
    return self
end

function ASSString:getTag(coerce)
    local val = self.value or ""
    if coerce and type(val)~= "string" then
        val = ""
    else self:typeCheck(val) end

    return val
end

function ASSString:append(str)
    return self:commonOp("append", function(val,str)
        return val..str
    end, "", str)
end

function ASSString:prepend(str)
    return self:commonOp("prepend", function(val,str)
        return str..val
    end, "", str)
end

function ASSString:replace(target,rep,useLuaPatterns)
    self.value = useLuaPatterns and self.value:gsub(target, rep) or re.sub(self.value,target,rep)
    return self.value
end

ASSString.add, ASSString.mul, ASSString.pow = ASSString.append, nil, nil

ASSClip = createASSClass("ASSClip", ASSBase, {}, {})
function ASSClip:new(arg1,arg2,arg3,arg4,tagProps)
    if type(arg1) == "table" then
        tagProps = arg2
        arg1,arg2,arg3,arg4 = unpack(arg1)
        if arg2 then
            arg1,arg2,arg3,arg4 = string.toNumbers(10,arg1,arg2,arg3,arg4)
        end
    end
    tagProps = tagProps or {}
    if type(arg1)=="number" then
        return ASSClipRect(arg1,arg2,arg3,arg4,tagProps)
    elseif type(arg1)=="string" then
        return ASSClipVect({arg1},tagProps)
    else error("Invalid argumets to ASSClip") end
end

ASSClipRect = createASSClass("ASSClipRect", ASSBase, {"topLeft", "bottomRight"}, {ASSPosition, ASSPosition})

function ASSClipRect:new(left,top,right,bottom,tagProps)
    if type(left) == "table" then
        tagProps = top
        left,top,right,bottom = self:getArgs(left, nil, true)
    end
    self:readProps(tagProps)
    self.topLeft = ASSPosition(left,top)
    self.bottomRight = ASSPosition(right,bottom)
    self:setInverse(self.__tag.inverse or false)
    return self
end

function ASSClipRect:getTag(coerce)
    self:setInverse(self.__tag.inverse or false)
    return returnAll({self.topLeft:getTag(coerce)}, {self.bottomRight:getTag(coerce)})
end

function ASSClipRect:setInverse(state)
    state = type(state)==nil and true or false
    self.__tag.inverse = state
    self.__tag.name = state and "iclipRect" or "clipRect"
    return state
end

function ASSClipRect:toggleInverse()
    return self:setInverse(not self.__tag.inverse)
end

ASSClipVect = createASSClass("ASSClipVect", ASSBase, {"commands"}, {"table"})

function ASSClipVect:new(...)
    --- two ways to create: [1] from string in a table [2] from list of ASSDraw objects
    local args, tagProps = {...}, {}
    self.commands = {}
    if #args==2 and type(args[1])=="table" and not args[1].instanceOf then
        local cmdTypes = {
            m = ASSDrawMove,
            n = ASSDrawMoveNc,
            l = ASSDrawLine,
            b = ASSDrawBezier
        }
        local cmdParts, cmdType, prmCnt, i = args[1][1]:split(" "), "", 0, 1
        while i<=#cmdParts do
            if cmdTypes[cmdParts[i]] then
                cmdType = cmdParts[i]
                prmCnt, i = #cmdTypes[cmdType].__meta__.order, i+1
            else 
                self.commands[#self.commands+1] = cmdTypes[cmdType](table.sliceArray(cmdParts,i,i+prmCnt-1))
                i=i+prmCnt
            end
        end
        tagProps = args[2]
    elseif type(args[1])=="table" then
        tagProps = args[#args].instanceOf and {} or table.remove(args)
        for i,arg in ipairs(args) do
            assert(arg.baseClass==ASSDrawBase, string.format("Error: argument %d to %s is not a drawing object.", i, self.typeName))
        end
        self.commands = args
    end
    self:readProps(tagProps)
    self:setInverse(self.__tag.inverse or false)
    return self
end

function ASSClipVect:getTag(coerce)
    self:setInverse(self.__tag.inverse or false)
    local cmdStr, lastCmdType
    for i,cmd in ipairs(self.commands) do
        if lastCmdType~=cmd.__tag.name then
            lastCmdType = cmd.__tag.name
            cmdStr =  i==1 and lastCmdType or cmdStr .. " " .. lastCmdType
        end
        cmdStr = cmdStr .. " " .. table.concat({cmd:getTag(coerce)}," ")
    end
    return cmdStr
end

--TODO: unify setInverse and toggleInverse for VectClip and RectClip by using multiple inheritance
function ASSClipVect:setInverse(state)
    state = type(state)==nil and true or state
    self.__tag.inverse = state
    self.__tag.name = state and "iclipVect" or "clipVect"
    return state
end

function ASSClipVect:toggleInverse()
    return self:setInverse(not self.__tag.inverse)
end

function ASSClipVect:commonOp(method, callback, default, x, y) -- drawing commands only have x and y in common
    local res = {}
    for _,command in ipairs(self.commands) do
        local subCnt = #command.__meta__.order
        res=table.join(res,{command[method](command,x,y)})
    end
    return unpack(res)
end

ASSClipVect.set, ASSClipVect.mod, ASSClipVect.get = nil, nil, nil  -- TODO: check if these can be remapped/implemented in a way that makes sense, maybe work on strings

ASSDrawBase = createASSClass("ASSDrawBase", ASSBase, {}, {})
function ASSDrawBase:new(...)
    local args = {...}
    if type(args[1]) == "table" then
        args = {self:getArgs(args[1], nil, true)}
    end
    for i,arg in ipairs(args) do
        self[self.__meta__.order[i]] = self.__meta__.types[i](arg) 
    end
    return self
end

function ASSDrawBase:getTag(coerce)
    local params={}
    for _,param in ipairs(self.__meta__.order) do
        params[#params+1] = self[param]:getTag(coerce)
    end
    return unpack(params)
end

ASSDrawMove = createASSClass("ASSDrawMove", ASSDrawBase, {"x","y"}, {ASSNumber, ASSNumber}, {name="m"})
ASSDrawMoveNc = createASSClass("ASSDrawMoveNc", ASSDrawBase, {"x","y"}, {ASSNumber, ASSNumber}, {name="n"})
ASSDrawLine = createASSClass("ASSDrawLine", ASSDrawBase, {"x","y"}, {ASSNumber, ASSNumber}, {name="l"})
ASSDrawBezier = createASSClass("ASSDrawBezier", ASSDrawBase, {"x1","y1","x2","y2","x3","y3"}, {ASSNumber, ASSNumber, ASSNumber, ASSNumber, ASSNumber, ASSNumber}, {name="b"})
--- TODO: b-spline support

function ASSDrawBezier:commonOp(method, callback, default, ...)
    local args, j, res = {...}, 1, {}
    if #args<=2 then -- special case to allow common operation on all x an y values of a vector drawing
        args[1], args[2] = args[1] or 0, args[2] or 0
        args = table.join(args,args,args)
    end
    args = {self:getArgs(args, default, false)}
    for _,valName in ipairs(self.__meta__.order) do
        local subCnt = #self[valName].__meta__.order
        res=table.join(res,{self[valName][method](self[valName],unpack(table.sliceArray(args,j,j+subCnt-1)))})
        j=j+subCnt
    end
    return unpack(res)
end
