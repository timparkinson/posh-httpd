$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")
. "$here\$sut"

Describe "New-HTTPRoute" {

    Context "when called without an alias" {
        
        $result = New-HTTPRoute 'blah' {}

        It "should return as get" {
            $result.method | Should be 'get'
        }
    }

    Context "when called with a correct alias" {
        $result = post 'blah' {}

        It "should return as the alias" {
            $result.method | Should be 'post'
        }
    }
}

Describe "ConvertTo-HTTPRoutePattern" {

    Context "when :parameter specified" {
        $parameter = "banana"
        $expected_result = "\(\?\<$parameter\>\\w\+\)"
        $pattern = "/blah/:$parameter"

        $result = ConvertTo-HTTPRoutePattern $pattern
        It "should return pattern with named parameter capture group" {
            $result | Should Match $expected_result
        }
    }

    Context "when multiple :parameter specified" {
        $parameter1 = "banana"
        $parameter2 = "apple"
        $expected_result = "\(\?\<$parameter1\>\\w\+\)\/\(\?\<$parameter2\>\\w\+\)"
        $pattern = "/blah/:$parameter1/:$parameter2"

        $result = ConvertTo-HTTPRoutePattern $pattern
        It "should return pattern with named parameter capture group" {
            $result | Should Match $expected_result
        }
    }

    Context "when splat specified" {
        $pattern = "/blah/*" 
        $expected_result = "\(\?\<splatted_param_1\>\.\*\)"

        $result = ConvertTo-HTTPRoutePattern $pattern
        It "should return pattern with splatted param capture group" {
            $result | Should Match $expected_result
        }
    }

    Context "when multiple splats specified" {
        $pattern = "/blah/*.*" 
        $expected_result = "\(\?\<splatted_param_1\>\.\*\).\(\?\<splatted_param_2\>\.\*\)"

        $result = ConvertTo-HTTPRoutePattern $pattern
        It "should return pattern with multiple splatted param capture group" {
            $result | Should Match $expected_result
        }
    }

    Context "when optional sections exist" {
        $parameter = "banana"
        $pattern = "/blah/?:$parameter`?"
        $expected_result = "\(\?\<$parameter\>\\w\+\)\?"

        $result = ConvertTo-HTTPRoutePattern $pattern
        It "should return pattern with optional param capture group" {
            $result | Should Match $expected_result
        }
    } 

}

Describe "Get-HTTPRouter" {

    Context "when called" {

    }
}