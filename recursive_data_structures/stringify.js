#!/usr/bin/node

const l = console.log;

function isObject(obj) {
    if (typeof obj === 'object' && !Array.isArray(obj) && obj !== null) {
        return true
    }
    else {
        return false
    }
}

function stringify(dsc) {
    const table = new Map;
    table.set(dsc, 1);
    return _stringify({ table: table, count: 1 }, dsc);
}

function _stringify(ref, dsc) {

    if (typeof dsc === 'undefined') {
        return "undefined"
    }

    if (isObject(dsc)) {
        return '{' + Object.entries(dsc)
            .map(([key,value]) => {
                    if (!ref.table.has(value)) {
                        ref.table.set(value, ref.count+1);
                        ref.count++;
                        return `"${key}":${ _stringify(ref, value) }`;
                    }
                    else {
                        return `"${key}":[ref ${ ref.table.get(value) }]`;
                    }
            }).join(',') + '}'
    }
    else if (Array.isArray(dsc)) {
        return '[' + dsc.map(e => {
            if (!ref.table.has(e)) {
                ref.table.set(e, ref.count+1);
                ref.count++;
                return _stringify(ref, e);
            }
            else {
                return `[ref ${ ref.table.get(e) }]`;
            }
        }).join(',') + ']'
    }
    else if (typeof dsc === 'function') {
        return `"[function]"`
    }
    else if (typeof dsc === 'string') {
        return `"${dsc}"`
    }
    else if (typeof dsc === 'number') {
        return `${dsc}`
    }
    else if (dsc === true) {
        return "true"
    }
    else if (dsc === false) {
        return "false"
    }
    else if (dsc === null) {
        return "null"
    }
}


// l(stringify(undefined));
// l(stringify(true));
// l(stringify(false));
// l(stringify(null));
// l(stringify(5));
// l(stringify(3.14));
// l(stringify("string"));
// l(stringify([5, "string"]));
// l(stringify([5, ["string"], { key: "value" } ]));


const inner = {
    key: "value",
    name: "inner"
};

const outter = {
    inner: inner,
};

outter.outter = outter;
outter.outter2 = outter;
 
l(stringify(outter))

const array = [];
array.push(1, 2, array);

l(stringify(array));





